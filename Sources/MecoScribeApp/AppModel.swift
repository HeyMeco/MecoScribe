import FluidAudio
import Foundation
import MecoScribeCore
import Observation

public enum TranscriptionPhase: Sendable, Equatable {
    case idle
    case inProgress(step: TranscriptionStep, detail: String?)
    case failed(at: TranscriptionStep?, message: String)
}

@Observable
public final class TranscriptionSettings {
    public var diarizationMode: ScribeProcessor.DiarizationMode = .offline
    public var threshold: Float = 0.6
    public var modelVersion: AsrModelVersion = .v3
    public var modelsDirectory: String = ""
    public var modelDir: String = ""
    public var presetSpeakerNames: [String] = []

    public init() {}

    public var speakerNameMap: [String: String] {
        Dictionary(
            uniqueKeysWithValues: presetSpeakerNames.enumerated().compactMap { index, name in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return ("speaker_\(index)", trimmed)
            }
        )
    }
}

@MainActor
@Observable
public final class AppModel {
    public var document: TranscriptDocument?
    public var fileWatcher: TranscriptFileWatcher?
    public var settings = TranscriptionSettings()
    public var transcriptionPhase: TranscriptionPhase = .idle
    public var transcribingAudioURL: URL?
    public var transcriptionTask: Task<Void, Never>?
    public var errorMessage: String?
    public var showSettings = false
    public var showConflictAlert = false

    public init() {}

    public func openTranscript(url: URL) {
        do {
            let doc = try TranscriptDocument.load(txtURL: url)
            openDocument(doc)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func openAudio(url: URL) {
        let baseName = url.deletingPathExtension().lastPathComponent
        let txtURL = url.deletingLastPathComponent().appendingPathComponent("\(baseName).txt")

        if FileManager.default.fileExists(atPath: txtURL.path) {
            do {
                let doc = try TranscriptDocument.load(txtURL: txtURL, audioURL: url)
                openDocument(doc)
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            startTranscription(audioURL: url)
        }
    }

    public func startTranscription(audioURL: URL, overwrite: Bool = false) {
        transcriptionTask?.cancel()
        transcribingAudioURL = audioURL
        transcriptionPhase = .inProgress(step: .preparing, detail: nil)
        errorMessage = nil

        transcriptionTask = Task { @MainActor in
            do {
                let modelsDirectory = try ModelCache.resolveDirectory(
                    customPath: settings.modelsDirectory.isEmpty ? nil : settings.modelsDirectory
                )
                let options = ScribeProcessor.Options(
                    diarizationMode: settings.diarizationMode,
                    threshold: settings.threshold,
                    modelVersion: settings.modelVersion,
                    modelsDirectory: modelsDirectory,
                    modelDir: settings.modelDir.isEmpty ? nil : settings.modelDir
                )

                let result = try await ScribeProcessor.process(
                    audioPath: audioURL.path,
                    options: options
                ) { update in
                    Task { @MainActor [self] in
                        transcriptionPhase = .inProgress(step: update.step, detail: update.detail)
                    }
                }

                transcriptionPhase = .inProgress(step: .saving, detail: nil)
                let doc = try TranscriptDocument.fromTranscription(
                    result: result,
                    speakerNames: settings.speakerNameMap,
                    audioURL: audioURL
                )

                openDocument(doc)
                transcriptionPhase = .idle
                transcribingAudioURL = nil
            } catch {
                if !Task.isCancelled {
                    let failedStep: TranscriptionStep?
                    if case .inProgress(let step, _) = transcriptionPhase {
                        failedStep = step
                    } else {
                        failedStep = nil
                    }
                    transcriptionPhase = .failed(at: failedStep, message: error.localizedDescription)
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    public func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        transcriptionPhase = .idle
        transcribingAudioURL = nil
    }

    public func closeDocument() {
        fileWatcher?.stop()
        fileWatcher = nil
        document = nil
    }

    public func handleExternalConflict(action: FileConflictAction) {
        guard let document else { return }
        switch action {
        case .reload:
            do {
                try document.reloadFromDisk()
                fileWatcher?.dismissConflict()
            } catch {
                errorMessage = error.localizedDescription
            }
        case .keepLocal:
            fileWatcher?.dismissConflict()
        }
        showConflictAlert = false
    }

    private func openDocument(_ doc: TranscriptDocument) {
        fileWatcher?.stop()
        document = doc
        let watcher = TranscriptFileWatcher(txtURL: doc.txtURL)
        fileWatcher = watcher
        doc.onDidSave = { [weak watcher] in
            watcher?.acknowledgeLocalSave()
        }
        watcher.start()
    }
}
