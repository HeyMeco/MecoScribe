import AppKit
import MecoScribeCore
import SwiftUI

struct EditorView: View {
    @Bindable var model: TranscriptEditorModel
    let closeProject: () -> Void
    @AppStorage(Preferences.showVideo) private var showVideo = true
    @AppStorage(Preferences.videoPaneHeight) private var videoHeight = 260.0

    var body: some View {
        VStack(spacing: 0) {
            banners
            PlayerBar(player: model.player)
            Divider()
            if model.player.hasVideo && showVideo {
                GeometryReader { proxy in
                    // Leave at least 220 pt for the speakers and transcript.
                    let maxHeight = max(120, proxy.size.height - 220)
                    VStack(spacing: 0) {
                        VideoPane(player: model.player)
                            .frame(height: min(videoHeight, maxHeight))
                        VideoResizeHandle(height: $videoHeight, range: 120...maxHeight)
                        transcriptArea
                    }
                }
            } else {
                transcriptArea
            }
            Divider()
            EditorStatusBar(model: model)
        }
        .background(KeyMonitor(handler: handleKey))
        .navigationTitle(model.title)
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .sheet(item: $model.speakerSheet) { sheet in
            SpeakerNameSheet(model: model, sheet: sheet)
        }
        .sheet(item: Binding(
            get: { model.mergeSourceSpeaker.map(SpeakerRef.init) },
            set: { model.mergeSourceSpeaker = $0?.id }
        )) { ref in
            MergeSpeakerSheet(model: model, sourceId: ref.id)
        }
        .alert(
            "Delete Speaker",
            isPresented: Binding(
                get: { model.deleteCandidateSpeaker != nil },
                set: { if !$0 { model.deleteCandidateSpeaker = nil } }
            ),
            presenting: model.deleteCandidateSpeaker
        ) { id in
            if model.utteranceCount(for: id) == 0 {
                Button("Delete", role: .destructive) { model.deleteSpeaker(id) }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { id in
            Text(deleteMessage(for: id))
        }
    }

    private var transcriptArea: some View {
        VStack(spacing: 0) {
            SpeakersPanel(model: model)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
            TranscriptView(model: model)
        }
    }

    private var subtitle: String {
        let speakers = model.speakerIds.count
        return "\(TextExporter.formatTime(model.durationSeconds)) · \(speakers) speaker\(speakers == 1 ? "" : "s")"
    }

    private func deleteMessage(for id: String) -> String {
        let name = model.speakerName(id)
        let count = model.utteranceCount(for: id)
        if count == 0 {
            return "\(name) has no transcriptions assigned and can be safely deleted."
        }
        let label = count == 1 ? "1 transcription" : "\(count) transcriptions"
        return "\(name) has \(label) assigned. Reassign them to another speaker, or merge the speaker, before deleting."
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Mode", selection: Binding(get: { model.editMode }, set: { model.setEditMode($0) })) {
                ForEach(EditMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Edit Mode (⌘1): edit words and select them to reassign speakers · Move Mode (⌘2): drag words to a new position")
        }
        ToolbarItem(placement: .navigation) {
            Button {
                closeProject()
            } label: {
                Label("Close Project", systemImage: "house")
            }
            .help("Close Project (⇧⌘W) and return to the home screen")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Button {
                    model.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .help("Undo (⌘Z)")
                .disabled(!model.canUndo)

                Button {
                    model.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .help("Redo (⇧⌘Z)")
                .disabled(!model.canRedo)
            }

            Button {
                model.saveExplicitly()
            } label: {
                Label("Save Now", systemImage: "arrow.down.doc")
            }
            .help("Save now (⌘S). Edits also save automatically.")

            Menu {
                Button("Export Transcript (.txt)…") { EditorActions.exportText(model) }
                Button("Export HTML Viewer…") { EditorActions.exportHTML(model) }
                Button("Export Separate Files…") { EditorActions.exportSeparateFiles(model) }
                Divider()
                Button("Show in Finder") { EditorActions.revealInFinder(model) }
                if model.audioURL == nil {
                    Button("Locate Audio…") { EditorActions.locateAudio(model) }
                }
                Divider()
                Button("Discard All Edits…", role: .destructive) { EditorActions.confirmDiscard(model) }
                    .disabled(!model.hasEditsSinceOpening)
                Divider()
                Button("Close Project") { closeProject() }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("Export and file actions")
        }
    }

    @ViewBuilder
    private var banners: some View {
        if model.externalChangeText != nil {
            Banner(
                systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                tint: .orange,
                message: "\(model.project.url.lastPathComponent) was changed in another app."
            ) {
                Button("Reload from File") { model.reloadFromDisk() }
                Button("Keep My Edits") { model.keepLocalEdits() }
            }
        }
        if model.audioURL == nil {
            Banner(
                systemImage: "speaker.slash",
                tint: .secondary,
                message: "Audio not found (\((model.sourceFile as NSString).lastPathComponent)). Playback is unavailable."
            ) {
                Button("Locate Audio…") { EditorActions.locateAudio(model) }
            }
        }
    }

    /// Window-level keys that must not reach text fields: Space plays/pauses, Esc
    /// cancels an edit or clears the selection, Delete removes selected words.
    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 53: // Esc
            return model.escape()
        case 49 where modifiers.isEmpty && !TextEditing.isActive: // Space
            model.player.togglePlayPause()
            return true
        case 51, 117: // Delete, Forward Delete
            guard modifiers.isEmpty, !TextEditing.isActive, model.editing == nil, !model.selection.isEmpty else {
                return false
            }
            model.deleteWords(model.selection)
            return true
        default:
            if modifiers.isEmpty, !TextEditing.isActive, model.assignMenuRect != nil,
                let digit = event.charactersIgnoringModifiers.flatMap(Int.init), (1...9).contains(digit)
            {
                return model.assignSelection(toSpeakerAt: digit - 1)
            }
            return false
        }
    }
}

private struct SpeakerRef: Identifiable {
    let id: String
}

private struct Banner<Actions: View>: View {
    let systemImage: String
    let tint: Color
    let message: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(message)
                .lineLimit(2)
            Spacer()
            actions()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct EditorStatusBar: View {
    let model: TranscriptEditorModel

    var body: some View {
        HStack(spacing: 12) {
            saveStatus
            Spacer()
            Text(model.editMode.hint)
                .foregroundStyle(.secondary)
            Text("·").foregroundStyle(.tertiary)
            Text("\(model.totalWords.formatted()) words")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var saveStatus: some View {
        if let error = model.saveError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if model.isSaving {
            Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
        } else if model.savePending || model.isDirty {
            Label("Saving soon…", systemImage: "circle.dotted")
                .foregroundStyle(.orange)
        } else if let saved = model.lastSavedAt {
            Label(
                "Saved \(model.project.url.lastPathComponent) at \(saved.formatted(date: .omitted, time: .standard))",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
        } else {
            Label("Live editing · saves automatically to \(model.project.url.lastPathComponent)", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        }
    }
}

/// Observes key-down events for the window that hosts it. The handler returns true to
/// swallow the event.
struct KeyMonitor: NSViewRepresentable {
    let handler: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyMonitorView {
        let view = KeyMonitorView()
        view.handler = handler
        return view
    }

    func updateNSView(_ view: KeyMonitorView, context: Context) {
        view.handler = handler
    }

    final class KeyMonitorView: NSView {
        var handler: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                nonisolated(unsafe) let event = event
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard
                        let self,
                        let window = self.window,
                        event.window === window,
                        window.attachedSheet == nil,
                        let handler = self.handler
                    else { return false }
                    return handler(event)
                }
                return handled ? nil : event
            }
        }

        override func removeFromSuperview() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            super.removeFromSuperview()
        }
    }
}
