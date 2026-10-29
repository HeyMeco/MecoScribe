import AVFoundation
import FluidAudio
import Foundation

public enum ScribeProcessor {
    private static let logger = AppLogger(category: "MecoScribe")

    public struct Options: Sendable {
        public var diarizationMode: DiarizationMode = .nemotron3
        public var threshold: Float = 0.6
        public var transcriptionModel: TranscriptionModel = .parakeet(.ultra)
        public var modelsDirectory: URL
        public var modelDir: String?
        /// Nemotron 3.5 language hint (`en-US`, `de-DE`, `auto`, …).
        public var language: String = "auto"
        /// Nemotron 3.5 chunk tier in milliseconds.
        public var chunkMs: Int = 2240

        public init(
            diarizationMode: DiarizationMode = .nemotron3,
            threshold: Float = 0.6,
            transcriptionModel: TranscriptionModel = .parakeet(.ultra),
            modelsDirectory: URL,
            modelDir: String? = nil,
            language: String = "auto",
            chunkMs: Int = 2240
        ) {
            self.diarizationMode = diarizationMode
            self.threshold = threshold
            self.transcriptionModel = transcriptionModel
            self.modelsDirectory = modelsDirectory
            self.modelDir = modelDir
            self.language = language
            self.chunkMs = chunkMs
        }
    }

    public enum DiarizationMode: String, Sendable, CaseIterable {
        case streaming
        case offline
        case nemotron3
    }

    public enum TranscriptionModel: Sendable {
        case parakeet(AsrModelVersion)
        case nemotron3
    }

    /// Pipeline stages reported to `process(audioPath:options:progress:)` callers.
    public enum Stage: Sendable, Equatable {
        /// Downloading (first run) or loading the speaker diarization models.
        case preparingDiarizationModels
        case diarizing
        /// Downloading (first run) or loading the speech recognition models.
        case preparingTranscriptionModels
        case transcribing
        case aligning
    }

    /// Download progress of the models being prepared in the current stage.
    public struct ModelProgress: Sendable, Equatable {
        public enum Phase: Sendable, Equatable {
            case listing
            case downloading(completedFiles: Int, totalFiles: Int)
            case compiling
        }

        /// While downloading: the fraction of the download done, in [0, 1].
        /// Otherwise FluidAudio's overall fraction for the operation.
        public var fractionCompleted: Double
        public var phase: Phase

        public init(fractionCompleted: Double, phase: Phase) {
            self.fractionCompleted = fractionCompleted
            self.phase = phase
        }
    }

    public enum ProgressEvent: Sendable, Equatable {
        case stage(Stage)
        case models(ModelProgress)
    }

    public typealias ProgressReporter = @Sendable (ProgressEvent) -> Void

    public static func process(
        audioPath: String,
        options: Options,
        progress: ProgressReporter? = nil
    ) async throws -> ScribeResult {
        let audioURL = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioPath) else {
            throw ScribeError.fileNotFound(audioPath)
        }

        logger.info("Using models cache: \(options.modelsDirectory.path)")
        logger.info("Diarizing audio (\(options.diarizationMode.rawValue) mode)...")
        let segments = try await diarize(audioPath: audioPath, options: options, progress: progress)
        let speakerIds = Array(Set(segments.map(\.speakerId))).sorted()
        try Task.checkCancellation()

        logger.info("Transcribing audio (\(modelLabel(for: options.transcriptionModel)))...")
        let wordTimings = try await transcribe(audioURL: audioURL, options: options, progress: progress)
        try Task.checkCancellation()

        logger.info("Aligning \(wordTimings.count) words to \(speakerIds.count) speakers...")
        progress?(.stage(.aligning))
        let utterances = WordSpeakerAligner.align(words: wordTimings, segments: segments)

        let duration: TimeInterval
        if let lastWord = wordTimings.last {
            duration = lastWord.endTime
        } else if let lastSegment = segments.max(by: { $0.endTimeSeconds < $1.endTimeSeconds }) {
            duration = TimeInterval(lastSegment.endTimeSeconds)
        } else {
            duration = 0
        }

        return ScribeResult(
            audioFile: audioPath,
            durationSeconds: duration,
            speakerCount: speakerIds.count,
            utterances: utterances,
            speakerIds: speakerIds
        )
    }

    /// Forwards FluidAudio download progress as `.models` events. FluidAudio gives the
    /// download a share of the whole operation (`downloadWeight`): 0.5 for repo loads,
    /// which compile afterwards, and 1.0 for subdirectory downloads.
    private static func downloadHandler(
        _ progress: ProgressReporter?,
        downloadWeight: Double
    ) -> ProgressHandler? {
        guard let progress else { return nil }
        return { update in
            let phase: ModelProgress.Phase
            var fraction = update.fractionCompleted
            switch update.phase {
            case .listing:
                phase = .listing
            case .downloading(let completed, let total):
                // Cached models report an empty download (0 of 0 files); skip it.
                guard total > 0 else { return }
                phase = .downloading(completedFiles: completed, totalFiles: total)
                fraction = min(max(fraction / downloadWeight, 0), 1)
            case .compiling:
                phase = .compiling
            }
            progress(.models(ModelProgress(fractionCompleted: fraction, phase: phase)))
        }
    }

    private static func diarize(
        audioPath: String,
        options: Options,
        progress: ProgressReporter?
    ) async throws -> [TimedSpeakerSegment] {
        progress?(.stage(.preparingDiarizationModels))
        switch options.diarizationMode {
        case .streaming:
            return try await diarizeStreaming(
                audioPath: audioPath,
                options: options,
                threshold: options.threshold,
                progress: progress
            )
        case .offline:
            return try await diarizeOffline(
                audioPath: audioPath,
                options: options,
                threshold: options.threshold,
                progress: progress
            )
        case .nemotron3:
            return try await diarizeNemotron3(audioPath: audioPath, options: options, progress: progress)
        }
    }

    private static func diarizeStreaming(
        audioPath: String,
        options: Options,
        threshold: Float,
        progress: ProgressReporter?
    ) async throws -> [TimedSpeakerSegment] {
        let config = DiarizerConfig(clusteringThreshold: threshold)
        let manager = DiarizerManager(config: config)
        let diarizerDir = ModelCache.diarizerDirectory(base: options.modelsDirectory)
        let models = try await DiarizerModels.downloadIfNeeded(
            to: diarizerDir,
            progressHandler: downloadHandler(progress, downloadWeight: 0.5)
        )
        manager.initialize(models: models)
        try Task.checkCancellation()
        progress?(.stage(.diarizing))

        let audioSamples = try AudioConverter().resampleAudioFile(path: audioPath)
        let result = try manager.performCompleteDiarization(audioSamples, sampleRate: 16_000)
        return result.segments
    }

    private static func diarizeOffline(
        audioPath: String,
        options: Options,
        threshold: Float,
        progress: ProgressReporter?
    ) async throws -> [TimedSpeakerSegment] {
        let offlineConfig = OfflineDiarizerConfig(clusteringThreshold: Double(threshold))
        let manager = OfflineDiarizerManager(config: offlineConfig)
        let models = try await OfflineDiarizerModels.load(
            from: options.modelsDirectory,
            progressHandler: downloadHandler(progress, downloadWeight: 0.5)
        )
        manager.initialize(models: models)
        try Task.checkCancellation()
        progress?(.stage(.diarizing))

        let audioURL = URL(fileURLWithPath: audioPath)
        let factory = AudioSourceFactory()
        let targetSampleRate = offlineConfig.segmentation.sampleRate
        let diskSourceResult = try factory.makeDiskBackedSource(
            from: audioURL,
            targetSampleRate: targetSampleRate
        )
        let diskSource = diskSourceResult.source
        defer { diskSource.cleanup() }

        let result = try await manager.process(
            audioSource: diskSource,
            audioLoadingSeconds: diskSourceResult.loadDuration
        ) { _, _ in }

        return result.segments
    }

    /// NVIDIA Nemotron 3 diarization (8-speaker Sortformer). Batch CLI uses the
    /// offline preset, which is the highest-quality profile.
    private static func diarizeNemotron3(
        audioPath: String,
        options: Options,
        progress: ProgressReporter?
    ) async throws -> [TimedSpeakerSegment] {
        let config = Nemotron3Config.offline
        logger.info("Loading Nemotron 3 diarization (offline preset)...")
        let models = try await Nemotron3Models.loadFromHuggingFace(
            config: config,
            cacheDirectory: options.modelsDirectory,
            progressHandler: downloadHandler(progress, downloadWeight: 1.0)
        )
        try Task.checkCancellation()
        progress?(.stage(.diarizing))
        let diarizer = Nemotron3Diarizer(config: config, models: models)
        let audioSamples = try AudioConverter().resampleAudioFile(path: audioPath)
        let (probabilities, frameCount) = try diarizer.processComplete(audioSamples)
        let segments = Nemotron3Diarizer.segments(
            probabilities: probabilities,
            frameCount: frameCount,
            threshold: options.threshold
        )
        return segments.map { segment in
            TimedSpeakerSegment(
                speakerId: "speaker_\(segment.speakerIndex)",
                embedding: [],
                startTimeSeconds: segment.startSeconds,
                endTimeSeconds: segment.endSeconds,
                qualityScore: 1
            )
        }
    }

    private static func transcribe(
        audioURL: URL,
        options: Options,
        progress: ProgressReporter?
    ) async throws -> [WordTiming] {
        progress?(.stage(.preparingTranscriptionModels))
        switch options.transcriptionModel {
        case .parakeet(let version):
            return try await transcribeParakeet(
                audioURL: audioURL,
                options: options,
                version: version,
                progress: progress
            )
        case .nemotron3:
            return try await transcribeNemotron3(audioURL: audioURL, options: options, progress: progress)
        }
    }

    private static func transcribeParakeet(
        audioURL: URL,
        options: Options,
        version: AsrModelVersion,
        progress: ProgressReporter?
    ) async throws -> [WordTiming] {
        let models: AsrModels
        if let modelDir = options.modelDir {
            models = try await AsrModels.load(
                from: URL(fileURLWithPath: modelDir),
                version: version
            )
        } else {
            let asrDir = ModelCache.asrDirectory(base: options.modelsDirectory, version: version)
            models = try await AsrModels.downloadAndLoad(
                to: asrDir,
                version: version,
                progressHandler: downloadHandler(progress, downloadWeight: 0.5)
            )
        }

        let tdtConfig = TdtConfig(blankId: version.blankId)
        let asrConfig = ASRConfig(
            tdtConfig: tdtConfig,
            encoderHiddenSize: version.encoderHiddenSize
        )
        let asrManager = AsrManager(config: asrConfig)
        try await asrManager.loadModels(models)
        try Task.checkCancellation()
        progress?(.stage(.transcribing))

        defer {
            Task { await asrManager.cleanup() }
        }

        var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
        let result = try await asrManager.transcribe(
            audioURL,
            decoderState: &decoderState
        )

        return WordTimingMerger.mergeTokensIntoWords(result.tokenTimings ?? [])
    }

    /// NVIDIA Nemotron 3.5 multilingual streaming ASR. Feeds the file in 60-second
    /// blocks and groups SentencePiece token timings into words.
    private static func transcribeNemotron3(
        audioURL: URL,
        options: Options,
        progress: ProgressReporter?
    ) async throws -> [WordTiming] {
        let modelDir: URL
        if let custom = options.modelDir {
            modelDir = URL(fileURLWithPath: custom)
        } else {
            logger.info(
                "Downloading Nemotron 3.5 (\(options.language) @ \(options.chunkMs)ms) if needed..."
            )
            modelDir = try await StreamingNemotronMultilingualAsrManager.downloadVariant(
                languageCode: options.language,
                chunkMs: options.chunkMs,
                to: options.modelsDirectory,
                progressHandler: downloadHandler(progress, downloadWeight: 1.0)
            )
        }

        let manager = StreamingNemotronMultilingualAsrManager()
        try await manager.loadModels(from: modelDir)
        await manager.setLanguage(options.language)
        try Task.checkCancellation()
        progress?(.stage(.transcribing))

        let audioFile = try AVAudioFile(forReading: audioURL)
        let converter = AudioConverter()
        let blockSeconds: Double = 60
        let blockFrames = AVAudioFrameCount(audioFile.processingFormat.sampleRate * blockSeconds)
        while audioFile.framePosition < audioFile.length {
            let remaining = AVAudioFrameCount(audioFile.length - audioFile.framePosition)
            let thisFrames = min(blockFrames, remaining)
            guard
                let block = AVAudioPCMBuffer(
                    pcmFormat: audioFile.processingFormat,
                    frameCapacity: thisFrames
                )
            else {
                throw ScribeError.invalidArgument("Failed to allocate an audio buffer")
            }
            try audioFile.read(into: block, frameCount: thisFrames)
            let samples = try converter.resampleBuffer(block)
            _ = try await manager.process(samples: samples)
        }

        let finished = try await manager.finishWithTokenTimings()
        if let detected = await manager.detectedLanguage() {
            logger.info("Nemotron detected language: \(detected)")
        }
        return WordTimingMerger.mergeTokensIntoWords(finished.timings)
    }

    private static func modelLabel(for model: TranscriptionModel) -> String {
        switch model {
        case .parakeet(.v2):
            return "English-only Parakeet v2"
        case .parakeet(.v3):
            return "multilingual Parakeet v3"
        case .parakeet(.redux):
            return "Parakeet Redux"
        case .parakeet(.ultra):
            return "Parakeet Ultra"
        case .parakeet(.tdtCtc110m):
            return "Parakeet tdt-ctc-110m"
        case .parakeet(.tdtJa):
            return "Parakeet tdt-ja"
        case .nemotron3:
            return "Nemotron 3.5 multilingual"
        }
    }
}

public enum ScribeError: LocalizedError {
    case fileNotFound(String)
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Audio file not found: \(path)"
        case .invalidArgument(let message):
            return message
        }
    }
}
