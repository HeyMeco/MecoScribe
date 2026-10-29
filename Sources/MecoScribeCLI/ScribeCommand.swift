import FluidAudio
import Foundation

enum ScribeCommand {
    static let version = "1.0.1"

    private static let logger = AppLogger(category: "MecoScribe")

    struct ParsedArgs {
        var audioFile: String?
        var outputDir: String?
        var diarizationMode: ScribeProcessor.DiarizationMode = .nemotron3
        var threshold: Float = 0.6
        var transcriptionModel: ScribeProcessor.TranscriptionModel = .parakeet(.ultra)
        var modelsDir: String?
        var modelDir: String?
        var language: String = "auto"
        var chunkMs: Int = 2240
        var speakerNames: [String: String] = [:]
        var htmlOnly = false
        var both = false
    }

    static func run(arguments: [String]) async {
        if arguments.contains("--version") || arguments.contains("-V") {
            print(version)
            exit(0)
        }

        if arguments.contains("--help") || arguments.contains("-h") {
            printUsage()
            exit(0)
        }

        guard let parsed = parseArguments(arguments) else {
            exit(1)
        }

        guard let audioFile = parsed.audioFile else {
            fputs("ERROR: No audio file specified\n", stderr)
            printUsage()
            exit(1)
        }

        let audioURL = URL(fileURLWithPath: audioFile)
        let baseName = audioURL.deletingPathExtension().lastPathComponent
        let outputDirectory = parsed.outputDir ?? audioURL.deletingLastPathComponent().path

        let txtPath = (outputDirectory as NSString).appendingPathComponent("\(baseName).txt")
        let htmlPath = (outputDirectory as NSString).appendingPathComponent("\(baseName).html")

        guard let choice = ExistingTranscriptPrompt.resolve(
            txtPath: txtPath,
            htmlOnlyFlag: parsed.htmlOnly,
            bothFlag: parsed.both
        ) else {
            exit(1)
        }

        do {
            try FileManager.default.createDirectory(
                atPath: outputDirectory,
                withIntermediateDirectories: true
            )

            switch choice {
            case .htmlOnly:
                logger.info("Generating HTML from existing transcript")
                let parsedTranscript = try TranscriptParser.parse(txtPath: txtPath, audioPath: audioFile)
                var speakerNames = parsedTranscript.speakerNames
                for (id, name) in parsed.speakerNames where !name.isEmpty {
                    speakerNames[id] = name
                }
                try HtmlExporter.export(
                    parsedTranscript.result,
                    audioPath: audioFile,
                    htmlPath: htmlPath,
                    speakerNames: speakerNames
                )
                let sidecarPath = TimingsSidecar.path(forTxtPath: txtPath)
                try TimingsSidecar.write(
                    TimingsSidecar(result: parsedTranscript.result, speakerNames: speakerNames),
                    to: sidecarPath
                )
                logger.info("Wrote interactive HTML: \(htmlPath)")
                print("HTML: \(htmlPath)")
                print("(kept existing transcript: \(txtPath))")

            case .both:
                logger.info("Processing: \(audioFile)")

                let modelsDirectory = try ModelCache.resolveDirectory(customPath: parsed.modelsDir)
                let options = ScribeProcessor.Options(
                    diarizationMode: parsed.diarizationMode,
                    threshold: parsed.threshold,
                    transcriptionModel: parsed.transcriptionModel,
                    modelsDirectory: modelsDirectory,
                    modelDir: parsed.modelDir,
                    language: parsed.language,
                    chunkMs: parsed.chunkMs
                )

                let result = try await ScribeProcessor.process(audioPath: audioFile, options: options)

                try TextExporter.export(result, speakerNames: parsed.speakerNames, to: txtPath)
                try HtmlExporter.export(
                    result,
                    audioPath: audioFile,
                    htmlPath: htmlPath,
                    speakerNames: parsed.speakerNames
                )
                let sidecarPath = TimingsSidecar.path(forTxtPath: txtPath)
                try TimingsSidecar.write(
                    TimingsSidecar(result: result, speakerNames: parsed.speakerNames),
                    to: sidecarPath
                )

                logger.info("Wrote transcript: \(txtPath)")
                logger.info("Wrote interactive HTML: \(htmlPath)")
                print("Transcript: \(txtPath)")
                print("HTML: \(htmlPath)")
                print("Timings: \(sidecarPath)")
            }
        } catch {
            fputs("ERROR: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func parseArguments(_ args: [String]) -> ParsedArgs? {
        var parsed = ParsedArgs()
        var i = 0

        while i < args.count {
            switch args[i] {
            case "--output-dir", "-o":
                guard i + 1 < args.count else {
                    fputs("ERROR: Missing value for \(args[i])\n", stderr)
                    return nil
                }
                parsed.outputDir = args[i + 1]
                i += 1
            case "--html-only":
                parsed.htmlOnly = true
            case "--both":
                parsed.both = true
            case "--mode":
                guard i + 1 < args.count else {
                    fputs("ERROR: Missing value for --mode\n", stderr)
                    return nil
                }
                guard let mode = ScribeProcessor.DiarizationMode(rawValue: args[i + 1].lowercased()) else {
                    fputs(
                        "ERROR: Invalid mode '\(args[i + 1])'. Use 'streaming', 'offline', or 'nemotron3'.\n",
                        stderr
                    )
                    return nil
                }
                parsed.diarizationMode = mode
                i += 1
            case "--threshold":
                guard i + 1 < args.count, let value = Float(args[i + 1]) else {
                    fputs("ERROR: Invalid --threshold value\n", stderr)
                    return nil
                }
                parsed.threshold = value
                i += 1
            case "--model-version":
                guard i + 1 < args.count else {
                    fputs("ERROR: Missing value for --model-version\n", stderr)
                    return nil
                }
                switch args[i + 1].lowercased() {
                case "v2", "2":
                    parsed.transcriptionModel = .parakeet(.v2)
                case "v3", "3":
                    parsed.transcriptionModel = .parakeet(.v3)
                case "ultra":
                    parsed.transcriptionModel = .parakeet(.ultra)
                case "phonon2", "phonon-2":
                    parsed.transcriptionModel = .parakeet(.phonon2)
                case "bark3", "bark-3":
                    parsed.transcriptionModel = .parakeet(.bark3)
                case "bark3-clean", "bark3clean":
                    parsed.transcriptionModel = .parakeet(.bark3Clean)
                case "nemotron3", "nemotron3.5", "nemotron":
                    parsed.transcriptionModel = .nemotron3
                case "transcribe-lite":
                    parsed.transcriptionModel = .transcribeLite
                default:
                    fputs(
                        "ERROR: Invalid model version '\(args[i + 1])'. Use 'v2', 'v3', 'ultra', 'phonon2', "
                            + "'bark3', 'bark3-clean', 'nemotron3' (alias 'nemotron3.5'), or 'transcribe-lite'.\n",
                        stderr
                    )
                    return nil
                }
                i += 1
            case "--language":
                guard i + 1 < args.count else {
                    fputs("ERROR: Missing value for --language\n", stderr)
                    return nil
                }
                parsed.language = args[i + 1]
                i += 1
            case "--chunk-ms":
                guard i + 1 < args.count, let value = Int(args[i + 1]) else {
                    fputs("ERROR: Invalid --chunk-ms value\n", stderr)
                    return nil
                }
                let allowed = [560, 1120, 2240, 4480]
                guard allowed.contains(value) else {
                    fputs("ERROR: --chunk-ms must be one of 560, 1120, 2240, 4480.\n", stderr)
                    return nil
                }
                parsed.chunkMs = value
                i += 1
            case "--models-dir":
                guard i + 1 < args.count else {
                    fputs("ERROR: Missing value for --models-dir\n", stderr)
                    return nil
                }
                parsed.modelsDir = args[i + 1]
                i += 1
            case "--model-dir":
                guard i + 1 < args.count else {
                    fputs("ERROR: Missing value for --model-dir\n", stderr)
                    return nil
                }
                parsed.modelDir = args[i + 1]
                i += 1
            case "--speakers":
                guard i + 1 < args.count else {
                    fputs("ERROR: Missing value for --speakers\n", stderr)
                    return nil
                }
                let names = args[i + 1].split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
                for (index, name) in names.enumerated() where !name.isEmpty {
                    parsed.speakerNames["speaker_\(index)"] = name
                }
                i += 1
            case let arg where arg.hasPrefix("-"):
                fputs("ERROR: Unknown option: \(arg)\n", stderr)
                return nil
            default:
                if parsed.audioFile == nil {
                    parsed.audioFile = args[i]
                } else {
                    fputs("ERROR: Unexpected argument: \(args[i])\n", stderr)
                    return nil
                }
            }
            i += 1
        }

        if parsed.htmlOnly && parsed.both {
            fputs("ERROR: Use only one of --html-only or --both\n", stderr)
            return nil
        }

        let supportsNemotronOptions: Bool
        switch parsed.transcriptionModel {
        case .nemotron3:
            supportsNemotronOptions = true
        case .parakeet, .transcribeLite:
            supportsNemotronOptions = false
        }
        if !supportsNemotronOptions {
            let languageChanged = parsed.language != "auto"
            let chunkChanged = parsed.chunkMs != 2240
            if languageChanged || chunkChanged {
                fputs("ERROR: --language and --chunk-ms apply only to --model-version nemotron3.\n", stderr)
                return nil
            }
        }

        return parsed
    }

    private static func printUsage() {
        let usage = """
        MecoScribe \(version) — diarized transcription powered by FluidAudio

        Usage:
            mecoscribe <audio_file> [options]

        Options:
            -o, --output-dir <dir>       Output directory (default: same as audio file)
            --html-only                  If .txt exists, regenerate HTML only
            --both                       If .txt exists, re-transcribe and overwrite both
            --models-dir <dir>           Model cache directory (default: ./models)
            --mode <streaming|offline|nemotron3>
                                         Diarization mode (default: nemotron3).
                                         nemotron3 uses NVIDIA Nemotron 3 (Apple Silicon);
                                         offline is the VBx pipeline
            --threshold <float>          Speaker clustering / activity threshold (default: 0.6)
            --model-version <name>       ASR model (default: ultra):
                                           ultra            Parakeet Ultra, multilingual (default)
                                           v3               Parakeet v3, multilingual
                                           v2               Parakeet v2, English-only
                                           phonon2          Phonon-2, English-only (macOS 15+)
                                           bark3            Bark 3.0, English-only, verbatim (macOS 15+)
                                           bark3-clean      Bark 3.0 Clean, English-only, drops
                                                            fillers and false starts (macOS 15+)
                                           nemotron3        Nemotron 3.5 ASR (streaming 0.6B),
                                                            multilingual, Apple Silicon
                                                            (alias: nemotron3.5)
                                           transcribe-lite  Nemotron 3.5 Transcribe Lite, English-only,
                                                            macOS 15+. Fast but LOW accuracy (~26% WER
                                                            on an AMI meeting); ~1.36 GB download
            --language <code>            Nemotron 3.5 ASR language hint (nemotron3 only, default: auto).
                                         Examples: en-US, de-DE, fr-FR, ja-JP, zh-CN
            --chunk-ms <560|1120|2240|4480>
                                         Nemotron 3.5 ASR latency tier (nemotron3 only, default: 2240)
            --model-dir <path>           Local ASR model directory (overrides cache)
            --speakers <n1,n2,...>       Preset speaker display names
            -h, --help                   Show this help
            -V, --version                Show version

        When <filename>.txt already exists, you will be asked whether to regenerate
        HTML only or re-transcribe both outputs (unless --html-only or --both is set).

        Output:
            <filename>.txt               Diarized plain-text transcript
            <filename>.mecoscribe.json   Word-level timings for the HTML viewer
            <filename>.html              Interactive transcript with highlighting,
                                         speaker renaming, and audio playback

        Examples:
            mecoscribe meeting.wav
            mecoscribe meeting.wav --html-only
            mecoscribe meeting.wav --both
            mecoscribe meeting.wav --mode offline --model-version v3
            mecoscribe meeting.wav --model-version nemotron3
            mecoscribe interview.mp3 --output-dir ./output --model-version nemotron3 --language de-DE
            mecoscribe meeting.wav --model-version transcribe-lite

        Requirements:
            macOS 14+ with Apple Silicon recommended (macOS 15+ for phonon2, bark3,
            bark3-clean and transcribe-lite). Models download automatically from
            Hugging Face on first run.

        """
        print(usage)
    }
}
