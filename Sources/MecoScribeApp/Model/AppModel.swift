import AppKit
import Foundation
import Observation

enum WindowRequest: Equatable {
    case open(URL)
    case newTranscription(audio: URL?)
}

/// App-wide state: recent transcripts, requests waiting for a window, open editors.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    private static let recentsKey = "recentTranscripts"
    private static let maxRecents = 12

    private(set) var recentFiles: [URL] = []
    /// Requests for a window that has not appeared yet (consumed by the next new window).
    @ObservationIgnored private var pendingRequests: [WindowRequest] = []
    @ObservationIgnored private var editors: [WeakEditor] = []
    /// Opens a new main window. Set from SwiftUI, which owns window creation; used by
    /// the app delegate when the Dock icon is clicked with no window open.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    private struct WeakEditor {
        weak var model: TranscriptEditorModel?
    }

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
        recentFiles = paths.map { URL(fileURLWithPath: $0) }
    }

    func noteRecent(_ project: ProjectFile) {
        let url = project.url
        recentFiles.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > Self.maxRecents {
            recentFiles.removeLast(recentFiles.count - Self.maxRecents)
        }
        UserDefaults.standard.set(recentFiles.map(\.path), forKey: Self.recentsKey)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func removeRecent(_ url: URL) {
        recentFiles.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        UserDefaults.standard.set(recentFiles.map(\.path), forKey: Self.recentsKey)
    }

    func clearRecents() {
        recentFiles.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.recentsKey)
    }

    func enqueue(_ request: WindowRequest) {
        pendingRequests.append(request)
    }

    func takePendingRequest() -> WindowRequest? {
        pendingRequests.isEmpty ? nil : pendingRequests.removeFirst()
    }

    func register(_ editor: TranscriptEditorModel) {
        editors.removeAll { $0.model == nil }
        editors.append(WeakEditor(model: editor))
    }

    /// Writes any pending edits before the app quits.
    func flushAllEditors() {
        for editor in editors.compactMap(\.model) {
            editor.close()
        }
    }
}

/// What one window is showing.
@MainActor
@Observable
final class Workspace {
    enum Phase {
        case welcome
        case setup(TranscriptionSetup)
        case transcribing(TranscriptionJob)
        case editor(TranscriptEditorModel)
    }

    private(set) var phase: Phase = .welcome
    var errorMessage: String?

    var isIdle: Bool {
        if case .welcome = phase { return true }
        return false
    }

    var editor: TranscriptEditorModel? {
        if case .editor(let editor) = phase { return editor }
        return nil
    }

    func handle(_ request: WindowRequest) {
        switch request {
        case .open(let url): open(url)
        case .newTranscription(let audio): startSetup(audio: audio)
        }
    }

    /// Opens a `.mscribe` project. Loose CLI files (`.txt`, `.mecoscribe.json`,
    /// `.html`) are imported into a `.mscribe` beside them; audio opens its project, or
    /// starts a transcription when it has none yet.
    func open(_ url: URL) {
        if ProjectLoader.isProject(url) {
            openProject(ProjectFile(url: url))
            return
        }
        let legacy = LegacyTranscriptFiles(fileURL: url)
        let project = legacy.project
        if ProjectLoader.isAudio(url) {
            if project.exists {
                openProject(project)
            } else if legacy.exists {
                importAndOpen(legacy)
            } else {
                startSetup(audio: url)
            }
            return
        }
        guard project.exists else {
            importAndOpen(legacy)
            return
        }
        switch confirmReimport(of: url, over: project) {
        case .openProject: openProject(project)
        case .replace: importAndOpen(legacy)
        case .cancel: break
        }
    }

    func openProject(_ project: ProjectFile) {
        do {
            let editor = try TranscriptEditorModel(project: project)
            closeCurrent()
            phase = .editor(editor)
            AppModel.shared.register(editor)
            AppModel.shared.noteRecent(project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importAndOpen(_ legacy: LegacyTranscriptFiles) {
        do {
            openProject(try ProjectLoader.importLegacy(legacy))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private enum ReimportChoice { case openProject, replace, cancel }

    private func confirmReimport(of url: URL, over project: ProjectFile) -> ReimportChoice {
        let alert = NSAlert()
        alert.messageText = "“\(project.url.lastPathComponent)” already exists"
        alert.informativeText =
            "Open the existing project, or replace it with the contents of “\(url.lastPathComponent)”?"
        alert.addButton(withTitle: "Open Project")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].hasDestructiveAction = true
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .openProject
        case .alertSecondButtonReturn: return .replace
        default: return .cancel
        }
    }

    func startSetup(audio: URL?) {
        closeCurrent()
        phase = .setup(TranscriptionSetup(audioURL: audio))
    }

    func startTranscription(_ request: TranscriptionRequest) {
        let job = TranscriptionJob(request: request)
        job.onSuccess = { [weak self] project in
            self?.openProject(project)
        }
        phase = .transcribing(job)
        job.start()
    }

    func cancelTranscription(returningTo setup: TranscriptionSetup) {
        if case .transcribing(let job) = phase {
            job.cancel()
        }
        phase = .setup(setup)
    }

    /// Saves and closes the open project (or abandons a setup) and shows the home screen.
    func closeProject() {
        guard !isIdle else { return }
        showWelcome()
    }

    func showWelcome() {
        closeCurrent()
        phase = .welcome
    }

    func closeCurrent() {
        switch phase {
        case .editor(let editor): editor.close()
        case .transcribing(let job): job.cancel()
        default: break
        }
    }
}
