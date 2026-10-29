import Foundation
import MecoScribeCore
import Observation

/// Form state for a new transcription; mirrors the CLI options.
@MainActor
@Observable
final class TranscriptionSetup {
    var audioURL: URL?
    /// nil means "same folder as the audio file".
    var outputDirectory: URL?
    var diarizationMode: ScribeProcessor.DiarizationMode
    var threshold: Double
    var asrChoice: ASRChoice
    var language: String
    var chunkMs: Int
    var speakerNamesText = ""
    var localModelDirectory: URL?

    init(audioURL: URL?) {
        let defaults = UserDefaults.standard
        self.audioURL = audioURL
        diarizationMode = ScribeProcessor.DiarizationMode(
            rawValue: defaults.string(forKey: Preferences.diarizationMode) ?? ""
        ) ?? .nemotron3
        threshold = defaults.double(forKey: Preferences.threshold)
        asrChoice = ASRChoice(rawValue: defaults.string(forKey: Preferences.asrModel) ?? "") ?? .ultra
        language = defaults.string(forKey: Preferences.language) ?? "auto"
        chunkMs = defaults.integer(forKey: Preferences.chunkMs)
        if !NemotronOptions.chunkTiers.contains(chunkMs) { chunkMs = 2240 }
    }

    var resolvedOutputDirectory: URL? {
        outputDirectory ?? audioURL?.deletingLastPathComponent()
    }

    /// The project this run would write.
    var targetProject: ProjectFile? {
        guard let audioURL, let directory = resolvedOutputDirectory else { return nil }
        return ProjectFile(directory: directory, baseName: audioURL.deletingPathExtension().lastPathComponent)
    }

    /// A transcript that already exists for this audio: a `.mscribe` in the output
    /// folder, or loose CLI files beside the audio.
    var existingTranscript: URL? {
        if let project = targetProject, project.exists { return project.url }
        guard let audioURL else { return nil }
        let legacy = LegacyTranscriptFiles(fileURL: audioURL)
        return FileManager.default.fileExists(atPath: legacy.txtURL.path) ? legacy.txtURL : nil
    }

    /// `--speakers "Alice,Bob"` → `speaker_0: Alice, speaker_1: Bob`.
    var speakerNames: [String: String] {
        var names: [String: String] = [:]
        let parts = speakerNamesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for (index, name) in parts.enumerated() where !name.isEmpty {
            names["speaker_\(index)"] = name
        }
        return names
    }

    func makeRequest() -> TranscriptionRequest? {
        guard let audioURL, let directory = resolvedOutputDirectory else { return nil }
        rememberAsDefaults()
        let isNemotron = asrChoice == .nemotron3
        let options = ScribeProcessor.Options(
            diarizationMode: diarizationMode,
            threshold: Float(threshold),
            transcriptionModel: asrChoice.model,
            modelsDirectory: Preferences.modelsDirectoryURL,
            modelDir: localModelDirectory?.path,
            language: isNemotron ? language : "auto",
            chunkMs: isNemotron ? chunkMs : 2240
        )
        return TranscriptionRequest(
            audioURL: audioURL,
            outputDirectory: directory,
            options: options,
            speakerNames: speakerNames
        )
    }

    private func rememberAsDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(diarizationMode.rawValue, forKey: Preferences.diarizationMode)
        defaults.set(threshold, forKey: Preferences.threshold)
        defaults.set(asrChoice.rawValue, forKey: Preferences.asrModel)
        defaults.set(language, forKey: Preferences.language)
        defaults.set(chunkMs, forKey: Preferences.chunkMs)
    }
}
