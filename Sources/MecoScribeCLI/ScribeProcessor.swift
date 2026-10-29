import AVFoundation
import FluidAudio
import Foundation

enum ScribeProcessor {
    private static let logger = AppLogger(category: "MecoScribe")

    struct Options {
        var diarizationMode: DiarizationMode = .nemotron3
        var threshold: Float = 0.6
        var transcriptionModel: TranscriptionModel = .parakeet(.ultra)
        var modelsDirectory: URL
        var modelDir: String?
        /// Nemotron 3.5 language hint (`en-US`, `de-DE`, `auto`, …).
        var language: String = "auto"
        /// Nemotron 3.5 chunk tier in milliseconds.
        var chunkMs: Int = 2240
    }

    enum DiarizationMode: String {
        case streaming
        case offline
        case nemotron3
    }

    enum TranscriptionModel {
        case parakeet(AsrModelVersion)
        case nemotron3
        /// Nemotron 3.5 Transcribe Lite (English, greedy CTC). Fast, low accuracy.
        case transcribeLite
    }

    static func process(audioPath: String, options: Options) async throws -> ScribeResult {
        let audioURL = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioPath) else {
            throw ScribeError.fileNotFound(audioPath)
        }

        // Fail before diarization rather than after it.
        if case .transcribeLite = options.transcriptionModel {
            guard #available(macOS 15, *) else {
                throw ScribeError.unsupportedPlatform(transcribeLitePlatformMessage)
            }
        }

        logger.info("Using models cache: \(options.modelsDirectory.path)")
        logger.info("Diarizing audio (\(options.diarizationMode.rawValue) mode)...")
        let segments = try await diarize(audioPath: audioPath, options: options)
        let speakerIds = Array(Set(segments.map(\.speakerId))).sorted()

        logger.info("Transcribing audio (\(modelLabel(for: options.transcriptionModel)))...")
        let wordTimings = try await transcribe(audioURL: audioURL, options: options)

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
        options: Options
    ) async throws -> [TimedSpeakerSegment] {
        switch options.diarizationMode {
        case .streaming:
            return try await diarizeStreaming(
                audioPath: audioPath,
                options: options,
                threshold: options.threshold
            )
        case .offline:
            return try await diarizeOffline(
                audioPath: audioPath,
                options: options,
                threshold: options.threshold
            )
        case .nemotron3:
            return try await diarizeNemotron3(audioPath: audioPath, options: options)
        }
    }

    private static func diarizeStreaming(
        audioPath: String,
        options: Options,
        threshold: Float
    ) async throws -> [TimedSpeakerSegment] {
        let config = DiarizerConfig(clusteringThreshold: threshold)
        let manager = DiarizerManager(config: config)
        let diarizerDir = ModelCache.diarizerDirectory(base: options.modelsDirectory)
        let models = try await DiarizerModels.downloadIfNeeded(to: diarizerDir)
        manager.initialize(models: models)

        let audioSamples = try AudioConverter().resampleAudioFile(path: audioPath)
        let result = try manager.performCompleteDiarization(audioSamples, sampleRate: 16_000)
        return result.segments
    }

    private static func diarizeOffline(
        audioPath: String,
        options: Options,
        threshold: Float
    ) async throws -> [TimedSpeakerSegment] {
        let offlineConfig = OfflineDiarizerConfig(clusteringThreshold: Double(threshold))
        let manager = OfflineDiarizerManager(config: offlineConfig)
        let models = try await OfflineDiarizerModels.load(from: options.modelsDirectory)
        manager.initialize(models: models)

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
        options: Options
    ) async throws -> [TimedSpeakerSegment] {
        let config = Nemotron3Config.offline
        logger.info("Loading Nemotron 3 diarization (offline preset)...")
        let models = try await Nemotron3Models.loadFromHuggingFace(
            config: config,
            cacheDirectory: options.modelsDirectory
        )
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
        options: Options
    ) async throws -> [WordTiming] {
        switch options.transcriptionModel {
        case .parakeet(let version):
            return try await transcribeParakeet(audioURL: audioURL, options: options, version: version)
        case .nemotron3:
            return try await transcribeNemotron3(audioURL: audioURL, options: options)
        case .transcribeLite:
            do {
                return try await transcribeLite(audioURL: audioURL, options: options)
            } catch ASRError.unsupportedPlatform {
                throw ScribeError.unsupportedPlatform(transcribeLitePlatformMessage)
            }
        }
    }

    private static func transcribeParakeet(
        audioURL: URL,
        options: Options,
        version: AsrModelVersion
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
                version: version
            )
        }

        let tdtConfig = TdtConfig(blankId: version.blankId)
        let asrConfig = ASRConfig(
            tdtConfig: tdtConfig,
            encoderHiddenSize: version.encoderHiddenSize
        )
        let asrManager = AsrManager(config: asrConfig)
        try await asrManager.loadModels(models)

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
        options: Options
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
                to: options.modelsDirectory
            )
        }

        let manager = StreamingNemotronMultilingualAsrManager()
        try await manager.loadModels(from: modelDir)
        await manager.setLanguage(options.language)

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

    private static let transcribeLitePlatformMessage =
        "--model-version transcribe-lite requires macOS 15 or newer (its Core ML models are macOS 15 ML Programs). "
        + "Use the default Parakeet Ultra on macOS 14."

    /// Nemotron 3.5 Transcribe Lite: encoder + CTC timestamp head without the LLM.
    /// Words carry only a start time; `inferWordEnds` fills in end times so
    /// `WordSpeakerAligner` gets a usable midpoint for every word.
    private static func transcribeLite(
        audioURL: URL,
        options: Options
    ) async throws -> [WordTiming] {
        let models: NemotronTranscribeLiteModels
        if let custom = options.modelDir {
            models = try NemotronTranscribeLiteModels.load(from: URL(fileURLWithPath: custom))
        } else {
            // Same as NemotronTranscribeLiteManager.load(), but cached under --models-dir
            // instead of FluidAudio's Application Support folder.
            logger.info("Downloading Nemotron 3.5 Transcribe Lite (~1.36 GB) if needed...")
            let liteDir = ModelCache.transcribeLiteDirectory(base: options.modelsDirectory)
            models = try await ModelHub.loadWithRecovery(
                .nemotron35TranscribeLite,
                directory: options.modelsDirectory,
                requiredFiles: ModelNames.NemotronTranscribeLite.requiredModels
            ) {
                try NemotronTranscribeLiteModels.load(from: liteDir)
            }
        }

        let manager = NemotronTranscribeLiteManager(models: models)
        try await manager.warmup()

        let samples = try AudioConverter().resampleAudioFile(audioURL)
        let result = try await manager.transcribe(audio: samples)

        return inferWordEnds(result.words, audioDuration: result.durationSeconds)
    }

    /// Longest span a Transcribe Lite word may cover. Without a cap, a pause after
    /// a word (or trailing silence after the last one) would be added to it,
    /// pushing its midpoint into the next speaker's turn and keeping it
    /// highlighted in the HTML through the silence.
    private static let transcribeLiteMaxWordSeconds: TimeInterval = 1.0

    /// Each word ends where the next one starts (or at the end of the audio),
    /// but never more than `transcribeLiteMaxWordSeconds` after its own start.
    static func inferWordEnds(
        _ words: [NemotronTranscribeLiteWord],
        audioDuration: TimeInterval
    ) -> [WordTiming] {
        words.indices.map { index in
            let start = words[index].start
            let nextStart = index + 1 < words.count ? words[index + 1].start : audioDuration
            let end = min(nextStart, start + transcribeLiteMaxWordSeconds)
            return WordTiming(
                word: words[index].text,
                startTime: start,
                endTime: max(start, end),
                confidence: 1
            )
        }
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
        case .parakeet(.phonon2):
            return "English-only Phonon-2"
        case .parakeet(.bark3):
            return "English-only Bark 3.0"
        case .parakeet(.bark3Clean):
            return "English-only Bark 3.0 Clean"
        case .nemotron3:
            return "Nemotron 3.5 ASR (streaming 0.6B)"
        case .transcribeLite:
            return "Nemotron 3.5 Transcribe Lite"
        }
    }
}

enum ScribeError: LocalizedError {
    case fileNotFound(String)
    case invalidArgument(String)
    case unsupportedPlatform(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Audio file not found: \(path)"
        case .invalidArgument(let message), .unsupportedPlatform(let message):
            return message
        }
    }
}
