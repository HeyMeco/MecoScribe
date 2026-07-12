import FluidAudio
import Foundation

public enum ScribeProcessor {
    private static let logger = AppLogger(category: "MecoScribe")

    public struct Options: Sendable {
        public var diarizationMode: DiarizationMode = .offline
        public var threshold: Float = 0.6
        public var modelVersion: AsrModelVersion = .v3
        public var modelsDirectory: URL
        public var modelDir: String?

        public init(
            diarizationMode: DiarizationMode = .offline,
            threshold: Float = 0.6,
            modelVersion: AsrModelVersion = .v3,
            modelsDirectory: URL,
            modelDir: String? = nil
        ) {
            self.diarizationMode = diarizationMode
            self.threshold = threshold
            self.modelVersion = modelVersion
            self.modelsDirectory = modelsDirectory
            self.modelDir = modelDir
        }
    }

    public enum DiarizationMode: String, Sendable {
        case streaming
        case offline
    }

    public typealias ProgressHandler = @Sendable (TranscriptionProgressUpdate) -> Void

    public static func process(
        audioPath: String,
        options: Options,
        onProgress: ProgressHandler? = nil
    ) async throws -> ScribeResult {
        func report(_ step: TranscriptionStep, detail: String? = nil) {
            onProgress?(TranscriptionProgressUpdate(step: step, detail: detail))
        }

        report(.preparing, detail: "Using models at \(options.modelsDirectory.path)")

        let audioURL = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioPath) else {
            throw ScribeError.fileNotFound(audioPath)
        }

        logger.info("Using models cache: \(options.modelsDirectory.path)")
        logger.info("Diarizing audio (\(options.diarizationMode.rawValue) mode)...")
        let segments = try await diarize(audioPath: audioPath, options: options, report: report)
        let speakerIds = Array(Set(segments.map(\.speakerId))).sorted()

        logger.info("Transcribing audio (\(modelLabel(for: options.modelVersion)))...")
        let wordTimings = try await transcribe(audioURL: audioURL, options: options, report: report)

        report(.aligning, detail: "Matching \(wordTimings.count) words to \(speakerIds.count) speakers")
        logger.info("Aligning \(wordTimings.count) words to \(speakerIds.count) speakers...")
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

    private static func diarize(
        audioPath: String,
        options: Options,
        report: @escaping (TranscriptionStep, String?) -> Void
    ) async throws -> [TimedSpeakerSegment] {
        switch options.diarizationMode {
        case .streaming:
            return try await diarizeStreaming(
                audioPath: audioPath,
                options: options,
                threshold: options.threshold,
                report: report
            )
        case .offline:
            return try await diarizeOffline(
                audioPath: audioPath,
                options: options,
                threshold: options.threshold,
                report: report
            )
        }
    }

    private static func diarizeStreaming(
        audioPath: String,
        options: Options,
        threshold: Float,
        report: @escaping (TranscriptionStep, String?) -> Void
    ) async throws -> [TimedSpeakerSegment] {
        report(.loadingDiarizerModels, "Streaming diarization models")
        let config = DiarizerConfig(clusteringThreshold: threshold)
        let manager = DiarizerManager(config: config)
        let diarizerDir = ModelCache.diarizerDirectory(base: options.modelsDirectory)
        let models = try await DiarizerModels.downloadIfNeeded(to: diarizerDir)
        manager.initialize(models: models)

        report(.diarizing, "Streaming mode")
        let audioSamples = try AudioConverter().resampleAudioFile(path: audioPath)
        let result = try manager.performCompleteDiarization(audioSamples, sampleRate: 16_000)
        return result.segments
    }

    private static func diarizeOffline(
        audioPath: String,
        options: Options,
        threshold: Float,
        report: @escaping (TranscriptionStep, String?) -> Void
    ) async throws -> [TimedSpeakerSegment] {
        report(.loadingDiarizerModels, "Offline diarization models")
        let offlineConfig = OfflineDiarizerConfig(clusteringThreshold: Double(threshold))
        let manager = OfflineDiarizerManager(config: offlineConfig)
        let models = try await OfflineDiarizerModels.load(from: options.modelsDirectory)
        manager.initialize(models: models)

        report(.diarizing, "Offline mode — this may take a while")
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

    private static func transcribe(
        audioURL: URL,
        options: Options,
        report: @escaping (TranscriptionStep, String?) -> Void
    ) async throws -> [WordTiming] {
        let modelLabel = modelLabel(for: options.modelVersion)
        report(.loadingSpeechModels, modelLabel)

        let models: AsrModels
        if let modelDir = options.modelDir {
            models = try await AsrModels.load(
                from: URL(fileURLWithPath: modelDir),
                version: options.modelVersion
            )
        } else {
            let asrDir = ModelCache.asrDirectory(base: options.modelsDirectory, version: options.modelVersion)
            models = try await AsrModels.downloadAndLoad(
                to: asrDir,
                version: options.modelVersion
            )
        }

        let tdtConfig = TdtConfig(blankId: options.modelVersion.blankId)
        let asrConfig = ASRConfig(
            tdtConfig: tdtConfig,
            encoderHiddenSize: options.modelVersion.encoderHiddenSize
        )
        let asrManager = AsrManager(config: asrConfig)
        try await asrManager.loadModels(models)

        defer {
            Task { await asrManager.cleanup() }
        }

        report(.transcribing, modelLabel)
        var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
        let result = try await asrManager.transcribe(
            audioURL,
            decoderState: &decoderState
        )

        return WordTimingMerger.mergeTokensIntoWords(result.tokenTimings ?? [])
    }

    private static func modelLabel(for version: AsrModelVersion) -> String {
        switch version {
        case .v2:
            return "English-only Parakeet v2"
        case .v3:
            return "multilingual Parakeet v3"
        case .tdtCtc110m:
            return "Parakeet tdt-ctc-110m"
        case .tdtJa:
            return "Parakeet tdt-ja"
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
