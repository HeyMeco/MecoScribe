import FluidAudio
import Foundation
import MecoScribeCore

enum ScribeCommand {
    private static let logger = AppLogger(category: "MecoScribe")

    struct ParsedArgs {
        var audioFile: String?
        var outputDir: String?
        var diarizationMode: ScribeProcessor.DiarizationMode = .offline
        var threshold: Float = 0.6
        var modelVersion: AsrModelVersion = .v3  // multilingual (default)
        var modelsDir: String?
        var modelDir: String?
        var speakerNames: [String: String] = [:]
        var htmlOnly = false
        var both = false
    }

    static func run(arguments: [String]) async {
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
                    modelVersion: parsed.modelVersion,
                    modelsDirectory: modelsDirectory,
                    modelDir: parsed.modelDir
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
                    fputs("ERROR: Invalid mode '\(args[i + 1])'. Use 'streaming' or 'offline'.\n", stderr)
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
                    parsed.modelVersion = .v2
                case "v3", "3":
                    parsed.modelVersion = .v3
                default:
                    fputs("ERROR: Invalid model version '\(args[i + 1])'. Use 'v2' or 'v3'.\n", stderr)
                    return nil
                }
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

        return parsed
    }

    private static func printUsage() {
        let usage = """
        MecoScribe — diarized transcription powered by FluidAudio

        Usage:
            mecoscribe <audio_file> [options]

        Options:
            -o, --output-dir <dir>       Output directory (default: same as audio file)
            --html-only                  If .txt exists, regenerate HTML only
            --both                       If .txt exists, re-transcribe and overwrite both
            --models-dir <dir>           Model cache directory (default: ./models)
            --mode <streaming|offline>   Diarization mode (default: offline)
            --threshold <float>          Speaker clustering threshold (default: 0.6)
            --model-version <v2|v3>      ASR model: v3 multilingual (default), v2 English-only
            --model-dir <path>           Local ASR model directory (overrides cache)
            --speakers <n1,n2,...>       Preset speaker display names
            -h, --help                   Show this help

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
            mecoscribe interview.mp3 --output-dir ./output

        Requirements:
            macOS 14+ with Apple Silicon recommended. Models download automatically
            from Hugging Face on first run.

        """
        print(usage)
    }
}
