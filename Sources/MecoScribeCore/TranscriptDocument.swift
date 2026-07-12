import Foundation
import Observation

public enum SaveStatus: Sendable, Equatable {
    case saved(Date)
    case dirty
    case saving
    case error(String)
}

@Observable
public final class TranscriptDocument: @unchecked Sendable {
    public private(set) var state: TranscriptState
    public private(set) var baseline: TranscriptState
    public private(set) var saveStatus: SaveStatus = .dirty

    public let audioURL: URL
    public let txtURL: URL
    public let sidecarURL: URL

    private var undoStack: [TranscriptState] = []
    private var redoStack: [TranscriptState] = []
    private let maxHistory = 100
    private var autoSaveTask: Task<Void, Never>?

    /// Called synchronously after a successful write to disk (manual or auto-save).
    public var onDidSave: (() -> Void)?

    public var isDirty: Bool {
        state != baseline
    }

    public init(result: ScribeResult, speakerNames: [String: String], audioURL: URL, txtURL: URL) {
        self.audioURL = audioURL
        self.txtURL = txtURL
        sidecarURL = URL(fileURLWithPath: TimingsSidecar.path(forTxtPath: txtURL.path))
        let initialState = TranscriptState(result: result, speakerNames: speakerNames)
        state = initialState
        baseline = initialState
    }

    public static func load(txtURL: URL, audioURL: URL? = nil) throws -> TranscriptDocument {
        let resolvedAudioURL: URL
        if let audioURL {
            resolvedAudioURL = audioURL
        } else {
            let parsed = try TranscriptParser.parse(txtPath: txtURL.path, audioPath: txtURL.path)
            resolvedAudioURL = resolveAudioURL(from: parsed.result.audioFile, relativeTo: txtURL)
            return TranscriptDocument(
                result: parsed.result,
                speakerNames: parsed.speakerNames,
                audioURL: resolvedAudioURL,
                txtURL: txtURL
            )
        }

        let parsed = try TranscriptParser.parse(txtPath: txtURL.path, audioPath: resolvedAudioURL.path)
        return TranscriptDocument(
            result: parsed.result,
            speakerNames: parsed.speakerNames,
            audioURL: resolvedAudioURL,
            txtURL: txtURL
        )
    }

    private static func resolveAudioURL(from audioFile: String, relativeTo txtURL: URL) -> URL {
        if (audioFile as NSString).isAbsolutePath {
            return URL(fileURLWithPath: audioFile)
        }
        let sibling = txtURL.deletingLastPathComponent().appendingPathComponent(audioFile)
        if FileManager.default.fileExists(atPath: sibling.path) {
            return sibling
        }
        return URL(fileURLWithPath: audioFile)
    }

    public static func fromTranscription(
        result: ScribeResult,
        speakerNames: [String: String],
        audioURL: URL,
        outputDirectory: URL? = nil
    ) throws -> TranscriptDocument {
        let directory = outputDirectory ?? audioURL.deletingLastPathComponent()
        let baseName = audioURL.deletingPathExtension().lastPathComponent
        let txtURL = directory.appendingPathComponent("\(baseName).txt")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try TextExporter.export(result, speakerNames: speakerNames, to: txtURL.path)
        let sidecar = TimingsSidecar(result: result, speakerNames: speakerNames)
        try TimingsSidecar.write(sidecar, to: TimingsSidecar.path(forTxtPath: txtURL.path))

        let document = TranscriptDocument(
            result: result,
            speakerNames: speakerNames,
            audioURL: audioURL,
            txtURL: txtURL
        )
        document.markSavedAsBaseline()
        return document
    }

    func markSavedAsBaseline() {
        baseline = state
        saveStatus = .saved(Date())
    }

    public func pushHistory() {
        undoStack.append(state)
        if undoStack.count > maxHistory {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    public func apply(_ newState: TranscriptState, recordHistory: Bool = true) {
        if recordHistory {
            pushHistory()
        }
        state = newState
        saveStatus = .dirty
        scheduleAutoSave()
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(state)
        state = previous
        saveStatus = .dirty
        scheduleAutoSave()
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(state)
        state = next
        saveStatus = .dirty
        scheduleAutoSave()
    }

    public func discardEdits() {
        pushHistory()
        state = baseline
        saveStatus = .dirty
        scheduleAutoSave()
    }

    public func save() throws {
        saveStatus = .saving
        let result = state.buildResult()
        try TextExporter.export(result, speakerNames: state.speakerNames, to: txtURL.path)
        let sidecar = TimingsSidecar(result: result, speakerNames: state.speakerNames)
        try TimingsSidecar.write(sidecar, to: sidecarURL.path)
        baseline = state
        saveStatus = .saved(Date())
        onDidSave?()
    }

    public func exportHTML(to htmlURL: URL) throws {
        try HtmlExporter.export(
            state.buildResult(),
            audioPath: audioURL.path,
            htmlPath: htmlURL.path,
            speakerNames: state.speakerNames
        )
    }

    public func reloadFromDisk() throws {
        let parsed = try TranscriptParser.parse(txtPath: txtURL.path, audioPath: audioURL.path)
        state = TranscriptState(result: parsed.result, speakerNames: parsed.speakerNames)
        baseline = state
        undoStack.removeAll()
        redoStack.removeAll()
        saveStatus = .saved(Date())
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            do {
                try self.save()
            } catch {
                self.saveStatus = .error(error.localizedDescription)
            }
        }
    }
}
