import AppKit
import MecoScribeCore
import SwiftUI

enum EditorEditMode: String, CaseIterable {
    case assign = "Assign speaker"
    case move = "Move words"
}

struct TranscriptEditorView: View {
    @Bindable var document: TranscriptDocument
    @Environment(AppModel.self) private var appModel
    @State private var player = AudioPlaybackModel()
    @State private var editMode: EditorEditMode = .assign
    @State private var selectedWordRefs: Set<WordRef> = []
    @State private var editingWordRef: WordRef?
    @State private var editingUtteranceIndex: Int?
    @State private var showRenameSheet = false
    @State private var showAddSpeakerSheet = false
    @State private var showDeleteSpeakerSheet = false
    @State private var activeSpeakerId: String?
    @State private var showAssignMenu = false
    @State private var draggedWordRefs: [WordRef] = []
    @State private var isDraggingSelection = false
    @State private var selectionDragStartFlat: Int?
    @State private var selectionAnchor: WordRef?
    @State private var dropPlacement: DropPlacement?

    var body: some View {
        VStack(spacing: 0) {
            TranscriptHeaderView(document: document)
            TranscriptToolbarView(
                document: document,
                onSave: { try? document.save() },
                onDiscard: { document.discardEdits() },
                onExportTXT: exportTXT,
                onExportHTML: exportHTML,
                onClose: { appModel.closeDocument() },
                onRetranscribe: { appModel.startTranscription(audioURL: document.audioURL, overwrite: true) }
            )
            PlayerPanelView(
                player: player,
                editMode: $editMode,
                canUndo: document.canUndo && editingWordRef == nil,
                canRedo: document.canRedo && editingWordRef == nil,
                onUndo: { document.undo() },
                onRedo: { document.redo() }
            )
            SpeakerChipsView(
                document: document,
                onRename: { speakerId in
                    activeSpeakerId = speakerId
                    showRenameSheet = true
                },
                onDelete: { speakerId in
                    activeSpeakerId = speakerId
                    showDeleteSpeakerSheet = true
                },
                onAdd: { showAddSpeakerSheet = true }
            )
            Divider()
            UtteranceListView(
                document: document,
                player: player,
                editMode: editMode,
                selectedWordRefs: $selectedWordRefs,
                editingWordRef: $editingWordRef,
                editingUtteranceIndex: $editingUtteranceIndex,
                draggedWordRefs: $draggedWordRefs,
                isDraggingSelection: $isDraggingSelection,
                selectionDragStartFlat: $selectionDragStartFlat,
                selectionAnchor: $selectionAnchor,
                dropPlacement: $dropPlacement,
                onWordEdit: commitWordEdit,
                onUtteranceEdit: commitUtteranceEdit,
                onInsertWord: insertWord,
                onAssignSelection: { showAssignMenu = true },
                onMoveWords: moveWords
            )
        }
        .onAppear {
            player.load(url: document.audioURL)
            player.trackUtterances(document.state.utterances)
        }
        .onChange(of: document.state.utterances) { _, utterances in
            player.trackUtterances(utterances)
        }
        .onChange(of: editMode) { _, _ in
            selectedWordRefs.removeAll()
            selectionAnchor = nil
            isDraggingSelection = false
            selectionDragStartFlat = nil
            dropPlacement = nil
            showAssignMenu = false
        }
        .onChange(of: selectedWordRefs) { _, refs in
            if refs.isEmpty {
                showAssignMenu = false
            }
        }
        .onDisappear {
            player.stop()
        }
        .sheet(isPresented: $showRenameSheet) {
            SpeakerNameSheet(
                title: "Rename Speaker",
                initialName: activeSpeakerId.map { SpeakerPalette.displayName(for: $0, speakerNames: document.state.speakerNames) } ?? ""
            ) { name in
                guard let speakerId = activeSpeakerId else { return }
                var state = document.state
                state = TranscriptEditor.renameSpeaker(speakerId, to: name, in: state)
                document.apply(state)
            }
        }
        .sheet(isPresented: $showAddSpeakerSheet) {
            SpeakerNameSheet(title: "Add Speaker", initialName: "") { name in
                let result = TranscriptEditor.addSpeaker(in: document.state, name: name)
                document.apply(result.state)
            }
        }
        .sheet(isPresented: $showDeleteSpeakerSheet) {
            DeleteSpeakerSheet(
                speakerName: activeSpeakerId.map { SpeakerPalette.displayName(for: $0, speakerNames: document.state.speakerNames) } ?? "",
                canDelete: activeSpeakerId.map { document.state.transcriptionCount(for: $0) == 0 } ?? false
            ) {
                guard let speakerId = activeSpeakerId,
                      let state = TranscriptEditor.deleteSpeaker(speakerId, in: document.state)
                else { return }
                document.apply(state)
            }
        }
        .popover(isPresented: $showAssignMenu, arrowEdge: .top) {
            SpeakerAssignMenu(
                speakerIds: document.state.speakerIds,
                speakerNames: document.state.speakerNames,
                onSelect: assignSelectedWords,
                onAddSpeaker: {
                    showAssignMenu = false
                    showAddSpeakerSheet = true
                }
            )
        }
        .sheet(isPresented: Binding(
            get: { editingUtteranceIndex != nil },
            set: { if !$0 { editingUtteranceIndex = nil } }
        )) {
            if let index = editingUtteranceIndex, document.state.utterances.indices.contains(index) {
                UtteranceEditSheet(
                    text: document.state.utterances[index].text,
                    onCommit: { commitUtteranceEdit(index: index, text: $0) },
                    onCancel: { editingUtteranceIndex = nil }
                )
            }
        }
    }

    private func commitWordEdit(ref: WordRef, text: String) {
        guard let state = TranscriptEditor.editWord(
            utteranceIndex: ref.utteranceIndex,
            wordIndex: ref.wordIndex,
            newText: text,
            in: document.state
        ) else { return }
        document.apply(state)
        editingWordRef = nil
    }

    private func commitUtteranceEdit(index: Int, text: String) {
        guard let state = TranscriptEditor.editUtterance(utteranceIndex: index, newText: text, in: document.state) else { return }
        document.apply(state)
        editingUtteranceIndex = nil
    }

    private func insertWord(utteranceIndex: Int, insertIndex: Int) {
        guard let result = TranscriptEditor.insertWord(utteranceIndex: utteranceIndex, insertIndex: insertIndex, in: document.state) else { return }
        document.apply(result.state)
        editingWordRef = result.editRef
    }

    private func assignSelectedWords(to speakerId: String) {
        let refs = Array(selectedWordRefs)
        guard let state = TranscriptEditor.assignWords(refs, toSpeaker: speakerId, in: document.state) else { return }
        document.apply(state)
        selectedWordRefs.removeAll()
        showAssignMenu = false
    }

    private func moveWords(toFlatIndex: Int, speakerId: String) {
        let refs = draggedWordRefs.isEmpty ? Array(selectedWordRefs) : draggedWordRefs
        guard let state = TranscriptEditor.moveWords(refs, toFlatIndex: toFlatIndex, speakerId: speakerId, in: document.state) else { return }
        document.apply(state)
        selectedWordRefs.removeAll()
        draggedWordRefs.removeAll()
        dropPlacement = nil
    }

    private func exportTXT() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = document.txtURL.lastPathComponent
        if panel.runModal() == .OK, let url = panel.url {
            try? FileManager.default.copyItem(at: document.txtURL, to: url)
        }
    }

    private func exportHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = document.txtURL.deletingPathExtension().lastPathComponent + ".html"
        if panel.runModal() == .OK, let url = panel.url {
            try? document.exportHTML(to: url)
        }
    }
}
