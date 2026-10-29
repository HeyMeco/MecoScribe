import AppKit
import UniformTypeIdentifiers

/// Open/save panels used by menus and views.
@MainActor
enum FilePanels {
    static func openTranscriptOrAudio() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Project or Audio"
        panel.message = "Choose a MecoScribe project (.mscribe), an audio file, or CLI output (.txt, .mecoscribe.json, .html) to import."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            ProjectFile.contentType, .plainText, .json, .html, .audio, .movie, .audiovisualContent,
        ]
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseAudio(message: String = "Choose an audio file to transcribe.") -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Audio"
        panel.message = message
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie, .audiovisualContent]
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseDirectory(title: String, startingAt directory: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func save(suggestedName: String, type: UTType, directory: URL) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [type]
        panel.directoryURL = directory
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Editor actions that need AppKit UI (panels, alerts).
@MainActor
enum EditorActions {
    static func exportText(_ editor: TranscriptEditorModel) {
        guard
            let url = FilePanels.save(
                suggestedName: editor.project.baseName + ".txt",
                type: .plainText,
                directory: editor.project.directory
            )
        else { return }
        do {
            try editor.exportText(to: url)
        } catch {
            showError("Could not export the transcript", error)
        }
    }

    static func exportHTML(_ editor: TranscriptEditorModel) {
        guard
            let url = FilePanels.save(
                suggestedName: editor.project.baseName + ".html",
                type: .html,
                directory: editor.project.directory
            )
        else { return }
        do {
            try editor.exportHTML(to: url)
        } catch {
            showError("Could not export the HTML viewer", error)
        }
    }

    /// Unpacks the project as the CLI's loose files into a folder of the user's choice.
    static func exportSeparateFiles(_ editor: TranscriptEditorModel) {
        guard
            let directory = FilePanels.chooseDirectory(
                title: "Export .txt, .mecoscribe.json and .html To",
                startingAt: editor.project.directory
            )
        else { return }
        let files = LegacyTranscriptFiles(directory: directory, baseName: editor.project.baseName)
        let existing = [files.txtURL, files.sidecarURL, files.htmlURL]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if !existing.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Replace existing files?"
            alert.informativeText = existing.map(\.lastPathComponent).joined(separator: ", ")
                + " already exist in “\(directory.lastPathComponent)”."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            alert.buttons.first?.hasDestructiveAction = true
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            let txt = try editor.exportSeparateFiles(to: directory)
            NSWorkspace.shared.activateFileViewerSelecting([txt])
        } catch {
            showError("Could not export the files", error)
        }
    }

    static func revealInFinder(_ editor: TranscriptEditorModel) {
        let url = editor.project.exists ? editor.project.url : editor.project.directory
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func locateAudio(_ editor: TranscriptEditorModel) {
        let name = (editor.sourceFile as NSString).lastPathComponent
        if let url = FilePanels.chooseAudio(message: "Locate the audio for this transcript (\(name)).") {
            editor.locateAudio(url)
        }
    }

    static func confirmDiscard(_ editor: TranscriptEditorModel) {
        let alert = NSAlert()
        alert.messageText = "Discard all edits?"
        alert.informativeText =
            "The transcript will be restored to how it was when you opened it. You can undo this."
        alert.addButton(withTitle: "Discard Edits")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            editor.discardEdits()
        }
    }

    static func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
