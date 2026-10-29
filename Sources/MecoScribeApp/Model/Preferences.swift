import Foundation
import MecoScribeCore

/// UserDefaults keys shared by `@AppStorage` views and model code.
enum Preferences {
    static let modelsDirectory = "modelsDirectory"
    static let diarizationMode = "diarizationMode"
    static let threshold = "threshold"
    static let asrModel = "asrModel"
    static let language = "language"
    static let chunkMs = "chunkMs"
    static let followPlayback = "followPlayback"
    static let playbackRate = "playbackRate"
    static let transcriptFontSize = "transcriptFontSize"
    static let showVideo = "showVideo"
    static let videoPaneHeight = "videoPaneHeight"
    static let checkForUpdatesAutomatically = "checkForUpdatesAutomatically"
    static let lastUpdateCheck = "lastUpdateCheck"
    static let skippedUpdateVersion = "skippedUpdateVersion"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            modelsDirectory: "",
            diarizationMode: ScribeProcessor.DiarizationMode.nemotron3.rawValue,
            threshold: 0.6,
            asrModel: ASRChoice.ultra.rawValue,
            language: "auto",
            chunkMs: 2240,
            followPlayback: false,
            playbackRate: 1.0,
            transcriptFontSize: 15.0,
            showVideo: true,
            videoPaneHeight: 260.0,
            checkForUpdatesAutomatically: true,
        ])
    }

    /// `~/Library/Application Support/MecoScribe/models`, unless `MECOSCRIBE_MODELS_DIR` is set.
    static var defaultModelsDirectory: URL {
        if let env = ProcessInfo.processInfo.environment["MECOSCRIBE_MODELS_DIR"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("MecoScribe", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
    }

    static var modelsDirectoryURL: URL {
        let custom = UserDefaults.standard.string(forKey: modelsDirectory) ?? ""
        return custom.isEmpty ? defaultModelsDirectory : URL(fileURLWithPath: custom, isDirectory: true)
    }
}

enum ASRChoice: String, CaseIterable, Identifiable {
    case ultra
    case v3
    case v2
    case nemotron3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ultra: return "Parakeet Ultra (multilingual)"
        case .v3: return "Parakeet v3 (multilingual)"
        case .v2: return "Parakeet v2 (English only)"
        case .nemotron3: return "Nemotron 3.5 (multilingual streaming)"
        }
    }

    var model: ScribeProcessor.TranscriptionModel {
        switch self {
        case .ultra: return .parakeet(.ultra)
        case .v3: return .parakeet(.v3)
        case .v2: return .parakeet(.v2)
        case .nemotron3: return .nemotron3
        }
    }
}

extension ScribeProcessor.DiarizationMode {
    var title: String {
        switch self {
        case .nemotron3: return "NVIDIA Nemotron 3 (up to 8 speakers)"
        case .offline: return "Offline VBx pipeline"
        case .streaming: return "Streaming"
        }
    }
}

enum NemotronOptions {
    static let chunkTiers = [560, 1120, 2240, 4480]
    static let languages = [
        "auto", "en-US", "en-GB", "de-DE", "fr-FR", "es-ES", "it-IT", "pt-BR", "nl-NL",
        "pl-PL", "sv-SE", "da-DK", "fi-FI", "nb-NO", "cs-CZ", "tr-TR", "ru-RU", "uk-UA",
        "ja-JP", "ko-KR", "zh-CN", "hi-IN", "ar-SA",
    ]
}
