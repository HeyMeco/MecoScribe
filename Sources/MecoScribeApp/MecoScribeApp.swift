import AppKit
import SwiftUI

@main
struct MecoScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Preferences.registerDefaults()
        // `MecoScribeApp path/to/transcript.txt` (or an audio file) opens it at launch.
        for argument in CommandLine.arguments.dropFirst() where !argument.hasPrefix("-") {
            let url = URL(fileURLWithPath: argument).standardizedFileURL
            if FileManager.default.fileExists(atPath: url.path) {
                AppModel.shared.enqueue(.open(url))
            }
        }
    }

    var body: some Scene {
        WindowGroup(id: WindowRoot.sceneID) {
            WindowRoot()
        }
        .defaultSize(width: 1040, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run MecoScribeApp`).
        NSApp.setActivationPolicy(.regular)
        Self.applyIconWhenUnbundled()
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            // Let the first window appear before any update alert.
            try? await Task.sleep(for: .seconds(3))
            await UpdatePrompt.checkAutomaticallyIfDue()
        }
    }

    /// The app bundle gets its icon from `CFBundleIconFile`. A bare executable has no
    /// Info.plist, so load the icon from the SwiftPM resource bundle next to it.
    /// (`Bundle.module` is avoided: it traps when the bundle is missing.)
    @MainActor private static func applyIconWhenUnbundled() {
        guard Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") == nil,
            let directory = Bundle.main.executableURL?.deletingLastPathComponent(),
            let resources = Bundle(url: directory.appendingPathComponent("MecoScribe_MecoScribeApp.bundle")),
            let url = resources.url(forResource: "MecoScribe", withExtension: "icns"),
            let icon = NSImage(contentsOf: url)
        else { return }
        NSApp.applicationIconImage = icon
    }

    /// Clicking the Dock icon (or opening the app again) with every window closed
    /// brings back a main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            if sender.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { return }
            // Minimized windows report canBecomeMain == false, so check them separately.
            if let minimized = sender.windows.first(where: \.isMiniaturized) {
                minimized.deminiaturize(nil)
            } else {
                AppModel.shared.openMainWindow?()
            }
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            AppModel.shared.flushAllEditors()
        }
        return .terminateNow
    }
}

// MARK: - Focused window

struct WorkspaceFocusKey: FocusedValueKey {
    typealias Value = Workspace
}

extension FocusedValues {
    var workspace: Workspace? {
        get { self[WorkspaceFocusKey.self] }
        set { self[WorkspaceFocusKey.self] = newValue }
    }
}

// MARK: - Menus

struct AppCommands: Commands {
    @FocusedValue(\.workspace) private var workspace
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Preferences.transcriptFontSize) private var fontSize = 15.0
    @AppStorage(Preferences.followPlayback) private var followPlayback = false
    @AppStorage(Preferences.showVideo) private var showVideo = true

    private var editor: TranscriptEditorModel? { workspace?.editor }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                Task { await UpdatePrompt.checkInteractively() }
            }
            .disabled(UpdateChecker.shared.state == .checking)
        }

        CommandGroup(replacing: .newItem) {
            Button("New Transcription…") {
                route(.newTranscription(audio: nil))
            }
            .keyboardShortcut("n")

            Button("New Window") {
                openWindow(id: WindowRoot.sceneID)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Open…") {
                if let url = FilePanels.openTranscriptOrAudio() {
                    route(.open(url))
                }
            }
            .keyboardShortcut("o")

            Menu("Open Recent") {
                ForEach(AppModel.shared.recentFiles, id: \.self) { url in
                    Button(url.deletingPathExtension().lastPathComponent) {
                        route(.open(url))
                    }
                }
                if !AppModel.shared.recentFiles.isEmpty {
                    Divider()
                    Button("Clear Menu") { AppModel.shared.clearRecents() }
                }
            }
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Now") { editor?.saveExplicitly() }
                .keyboardShortcut("s")
                .disabled(editor == nil)

            Divider()

            Button("Export Transcript (.txt)…") {
                if let editor { EditorActions.exportText(editor) }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(editor == nil)

            Button("Export HTML Viewer…") {
                if let editor { EditorActions.exportHTML(editor) }
            }
            .disabled(editor == nil)

            Button("Export Separate Files…") {
                if let editor { EditorActions.exportSeparateFiles(editor) }
            }
            .disabled(editor == nil)

            Button("Show in Finder") {
                if let editor { EditorActions.revealInFinder(editor) }
            }
            .disabled(editor == nil)

            Divider()

            Button("Close Project") { workspace?.closeProject() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(workspace?.isIdle ?? true)
        }

        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                if TextEditing.isActive {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                } else {
                    editor?.undo()
                }
            }
            .keyboardShortcut("z")
            .disabled(editor == nil || (editor?.editing == nil && !(editor?.canUndo ?? false)))

            Button("Redo") {
                if TextEditing.isActive {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                } else {
                    editor?.redo()
                }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(editor == nil || (editor?.editing == nil && !(editor?.canRedo ?? false)))
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Select All Words") { editor?.selectAll() }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(editor == nil)
        }

        CommandMenu("Transcript") {
            ForEach(Array(EditMode.allCases.enumerated()), id: \.element) { index, mode in
                Button {
                    editor?.setEditMode(mode)
                } label: {
                    if editor?.editMode == mode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                .disabled(editor == nil)
            }

            Divider()

            Button("Add Speaker…") { editor?.requestAddSpeaker() }
                .disabled(editor == nil)

            Button("Discard All Edits…") {
                if let editor { EditorActions.confirmDiscard(editor) }
            }
            .disabled(!(editor?.hasEditsSinceOpening ?? false))

            Divider()

            Button("Bigger Text") { fontSize = min(fontSize + 1, 28) }
                .keyboardShortcut("+")
            Button("Smaller Text") { fontSize = max(fontSize - 1, 11) }
                .keyboardShortcut("-")
            Button("Default Text Size") { fontSize = 15 }
                .keyboardShortcut("0")
        }

        CommandMenu("Playback") {
            Button(editor?.player.isPlaying == true ? "Pause" : "Play") {
                editor?.player.togglePlayPause()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(!(editor?.player.hasAudio ?? false))

            Button("Back 5 Seconds") { editor?.player.skip(by: -5) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(!(editor?.player.hasAudio ?? false))

            Button("Forward 5 Seconds") { editor?.player.skip(by: 5) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(!(editor?.player.hasAudio ?? false))

            Divider()

            Menu("Speed") {
                ForEach(AudioPlayerModel.rates, id: \.self) { rate in
                    Button {
                        editor?.player.rate = rate
                    } label: {
                        if editor?.player.rate == rate {
                            Label(PlayerBar.rateLabel(rate), systemImage: "checkmark")
                        } else {
                            Text(PlayerBar.rateLabel(rate))
                        }
                    }
                }
            }
            .disabled(editor == nil)

            Toggle("Follow Playback", isOn: $followPlayback)

            Toggle("Show Video", isOn: $showVideo)
                .keyboardShortcut("v", modifiers: [.command, .option])
                .disabled(!(editor?.player.hasVideo ?? false))
        }
    }

    /// Handles a request in the focused window if it is idle, else in a new window.
    private func route(_ request: WindowRequest) {
        if let workspace, workspace.isIdle {
            workspace.handle(request)
        } else {
            AppModel.shared.enqueue(request)
            openWindow(id: WindowRoot.sceneID)
        }
    }
}

enum TextEditing {
    /// True while a text field or text view has keyboard focus.
    @MainActor static var isActive: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }
}
