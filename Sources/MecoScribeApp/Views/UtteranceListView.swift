import AppKit
import MecoScribeCore
import SwiftUI

struct UtteranceLayoutContext {
    let speakerIds: [String]
    let speakerNames: [String: String]
    let utteranceCount: Int
    private let flatIndexStarts: [Int]

    init(state: TranscriptState) {
        speakerIds = state.speakerIds
        speakerNames = state.speakerNames
        utteranceCount = state.utterances.count
        var starts: [Int] = []
        var running = 0
        for utterance in state.utterances {
            starts.append(running)
            running += utterance.words.count
        }
        flatIndexStarts = starts
    }

    func flatIndexStart(for utteranceIndex: Int) -> Int {
        flatIndexStarts[utteranceIndex]
    }

    func flatIndex(utteranceIndex: Int, wordIndex: Int) -> Int {
        flatIndexStarts[utteranceIndex] + wordIndex
    }
}

struct UtteranceListView: View {
    @Bindable var document: TranscriptDocument
    @Bindable var player: AudioPlaybackModel
    let editMode: EditorEditMode
    @Binding var selectedWordRefs: Set<WordRef>
    @Binding var editingWordRef: WordRef?
    @Binding var editingUtteranceIndex: Int?
    @Binding var draggedWordRefs: [WordRef]
    @Binding var isDraggingSelection: Bool
    @Binding var selectionDragStartFlat: Int?
    @Binding var selectionAnchor: WordRef?
    @Binding var dropPlacement: DropPlacement?
    let onWordEdit: (WordRef, String) -> Void
    let onUtteranceEdit: (Int, String) -> Void
    let onInsertWord: (Int, Int) -> Void
    let onAssignSelection: () -> Void
    let onMoveWords: (Int, String) -> Void

    var body: some View {
        let layout = UtteranceLayoutContext(state: document.state)
        let utterances = document.state.utterances
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(Array(utterances.enumerated()), id: \.offset) { index, utterance in
                    let highlight = player.playbackHighlight
                    UtteranceCardView(
                        utterance: utterance,
                        utteranceIndex: index,
                        flatIndexStart: layout.flatIndexStart(for: index),
                        speakerIds: layout.speakerIds,
                        speakerNames: layout.speakerNames,
                        editMode: editMode,
                        selectedWordIndices: selectedIndices(in: index),
                        editingWordRef: editingWordRef,
                        dropPlacement: dropPlacement,
                        isDraggingSelection: isDraggingSelection,
                        isPlaybackActive: highlight?.utteranceIndex == index,
                        activeWordIndex: highlight?.utteranceIndex == index ? highlight?.wordIndex : nil,
                        onSelectWord: selectWord,
                        onWordEdit: onWordEdit,
                        onBeginWordEdit: { editingWordRef = $0 },
                        onUtteranceEdit: { editingUtteranceIndex = index },
                        onInsertWord: onInsertWord,
                        onMoveWords: onMoveWords,
                        onSeek: { player.playFrom($0) },
                        onDragStart: { draggedWordRefs = $0 },
                        onDropTargetChange: updateDropTarget,
                        onSelectionDragStart: { beginSelectionDrag(at: $0, layout: layout) },
                        onSelectionDragEnter: { extendSelectionDrag(toFlatIndex: $0) },
                        onSelectionDragEnd: finishSelectionDrag
                    )
                    .equatable()
                }
            }
            .padding()
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
    }

    private func selectedIndices(in utteranceIndex: Int) -> Set<Int> {
        Set(
            selectedWordRefs
                .filter { $0.utteranceIndex == utteranceIndex }
                .map(\.wordIndex)
        )
    }

    private func updateDropTarget(_ placement: DropPlacement, isTargeted: Bool) {
        if isTargeted {
            dropPlacement = placement
        } else if dropPlacement == placement {
            dropPlacement = nil
        }
    }

    private func selectWord(_ ref: WordRef, modifiers: NSEvent.ModifierFlags) {
        switch editMode {
        case .assign:
            if modifiers.contains(.command) {
                if selectedWordRefs.contains(ref) {
                    selectedWordRefs.remove(ref)
                } else {
                    selectedWordRefs.insert(ref)
                }
                selectionAnchor = ref
                if !selectedWordRefs.isEmpty {
                    onAssignSelection()
                }
            } else if modifiers.contains(.shift), let anchor = selectionAnchor {
                selectedWordRefs = TranscriptEditor.wordRefs(
                    inFlatRange: flatRange(from: anchor, to: ref),
                    utterances: document.state.utterances
                )
                if !selectedWordRefs.isEmpty {
                    onAssignSelection()
                }
            } else {
                selectedWordRefs = [ref]
                selectionAnchor = ref
                if !selectedWordRefs.isEmpty {
                    onAssignSelection()
                }
            }
        case .move:
            let utterance = document.state.utterances[ref.utteranceIndex]
            guard utterance.words.indices.contains(ref.wordIndex) else { return }
            player.playFrom(utterance.words[ref.wordIndex].startTime)
        }
    }

    private func beginSelectionDrag(at ref: WordRef, layout: UtteranceLayoutContext) {
        guard editMode == .assign, !isDraggingSelection else { return }
        isDraggingSelection = true
        selectionDragStartFlat = layout.flatIndex(utteranceIndex: ref.utteranceIndex, wordIndex: ref.wordIndex)
        if NSEvent.modifierFlags.contains(.command) {
            selectedWordRefs.insert(ref)
        } else {
            selectedWordRefs = [ref]
        }
        selectionAnchor = ref
    }

    private func extendSelectionDrag(toFlatIndex flatIndex: Int) {
        guard editMode == .assign, isDraggingSelection, let start = selectionDragStartFlat else { return }
        let range = min(start, flatIndex)...max(start, flatIndex)
        let newSelection = TranscriptEditor.wordRefs(
            inFlatRange: range,
            utterances: document.state.utterances
        )
        guard newSelection != selectedWordRefs else { return }
        selectedWordRefs = newSelection
    }

    private func finishSelectionDrag() {
        guard editMode == .assign, isDraggingSelection else { return }
        isDraggingSelection = false
        selectionDragStartFlat = nil
        if !selectedWordRefs.isEmpty {
            onAssignSelection()
        }
    }

    private func flatRange(from start: WordRef, to end: WordRef) -> ClosedRange<Int> {
        let utterances = document.state.utterances
        let startFlat = TranscriptEditor.flatIndex(
            utteranceIndex: start.utteranceIndex,
            wordIndex: start.wordIndex,
            utterances: utterances
        )
        let endFlat = TranscriptEditor.flatIndex(
            utteranceIndex: end.utteranceIndex,
            wordIndex: end.wordIndex,
            utterances: utterances
        )
        return min(startFlat, endFlat)...max(startFlat, endFlat)
    }
}

@MainActor
struct UtteranceCardView: View, Equatable {
    let utterance: DiarizedUtterance
    let utteranceIndex: Int
    let flatIndexStart: Int
    let speakerIds: [String]
    let speakerNames: [String: String]
    let editMode: EditorEditMode
    let selectedWordIndices: Set<Int>
    let editingWordRef: WordRef?
    let dropPlacement: DropPlacement?
    let isDraggingSelection: Bool
    let isPlaybackActive: Bool
    let activeWordIndex: Int?
    let onSelectWord: (WordRef, NSEvent.ModifierFlags) -> Void
    let onWordEdit: (WordRef, String) -> Void
    let onBeginWordEdit: (WordRef) -> Void
    let onUtteranceEdit: () -> Void
    let onInsertWord: (Int, Int) -> Void
    let onMoveWords: (Int, String) -> Void
    let onSeek: (TimeInterval) -> Void
    let onDragStart: ([WordRef]) -> Void
    let onDropTargetChange: (DropPlacement, Bool) -> Void
    let onSelectionDragStart: (WordRef) -> Void
    let onSelectionDragEnter: (Int) -> Void
    let onSelectionDragEnd: () -> Void

    private var speakerColor: Color {
        Color(hex: SpeakerPalette.color(for: utterance.speakerId, speakerIds: speakerIds))
    }

    nonisolated static func == (lhs: UtteranceCardView, rhs: UtteranceCardView) -> Bool {
        lhs.utterance == rhs.utterance
            && lhs.utteranceIndex == rhs.utteranceIndex
            && lhs.flatIndexStart == rhs.flatIndexStart
            && lhs.editMode == rhs.editMode
            && lhs.selectedWordIndices == rhs.selectedWordIndices
            && lhs.editingWordRef == rhs.editingWordRef
            && lhs.dropPlacement == rhs.dropPlacement
            && lhs.isDraggingSelection == rhs.isDraggingSelection
            && lhs.isPlaybackActive == rhs.isPlaybackActive
            && lhs.activeWordIndex == rhs.activeWordIndex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(SpeakerPalette.displayName(for: utterance.speakerId, speakerNames: speakerNames))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(speakerColor)
                Text(TranscriptFormatting.formatTime(utterance.startTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            FlowLayout(spacing: 2) {
                WordInsertGap(
                    utteranceIndex: utteranceIndex,
                    insertIndex: 0,
                    editMode: editMode,
                    flatIndex: flatIndexStart,
                    dropPlacement: dropPlacement,
                    onInsert: onInsertWord,
                    onMoveWords: { onMoveWords($0, utterance.speakerId) },
                    onDropTargetChange: onDropTargetChange
                )

                ForEach(Array(utterance.words.enumerated()), id: \.offset) { wordIndex, word in
                    let ref = WordRef(utteranceIndex: utteranceIndex, wordIndex: wordIndex)
                    let flat = flatIndexStart + wordIndex

                    WordSpanView(
                        word: word,
                        ref: ref,
                        speakerColor: speakerColor,
                        isActive: activeWordIndex == wordIndex,
                        isSelected: selectedWordIndices.contains(wordIndex),
                        isEditing: editingWordRef == ref,
                        editMode: editMode,
                        flatIndex: flat,
                        dropPlacement: dropPlacement,
                        isDraggingSelection: isDraggingSelection,
                        onTap: { onSelectWord(ref, NSEvent.modifierFlags) },
                        onEdit: { onWordEdit(ref, $0) },
                        onBeginEdit: { onBeginWordEdit(ref) },
                        onDragStart: { onDragStart(refsForDrag(ref: ref)) },
                        onDrop: { onMoveWords($0, utterance.speakerId) },
                        onSeek: { onSeek(word.startTime) },
                        onSelectionDragStart: { onSelectionDragStart(ref) },
                        onSelectionDragEnter: { onSelectionDragEnter(flat) },
                        onSelectionDragEnd: onSelectionDragEnd,
                        onDropTargetChange: onDropTargetChange
                    )
                    .equatable()

                    WordInsertGap(
                        utteranceIndex: utteranceIndex,
                        insertIndex: wordIndex + 1,
                        editMode: editMode,
                        flatIndex: flat + 1,
                        dropPlacement: dropPlacement,
                        onInsert: onInsertWord,
                        onMoveWords: { onMoveWords($0, utterance.speakerId) },
                        onDropTargetChange: onDropTargetChange
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isPlaybackActive ? speakerColor : Color.secondary.opacity(0.2), lineWidth: isPlaybackActive ? 2 : 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(speakerColor)
                .frame(width: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onUtteranceEdit() }
        .contextMenu {
            Button("Play from here") { onSeek(utterance.startTime) }
            Button("Edit utterance") { onUtteranceEdit() }
        }
    }

    private func refsForDrag(ref: WordRef) -> [WordRef] {
        if selectedWordIndices.contains(ref.wordIndex) {
            return selectedWordIndices.map { WordRef(utteranceIndex: utteranceIndex, wordIndex: $0) }
        }
        return [ref]
    }
}

struct WordInsertGap: View {
    let utteranceIndex: Int
    let insertIndex: Int
    let editMode: EditorEditMode
    let flatIndex: Int
    let dropPlacement: DropPlacement?
    let onInsert: (Int, Int) -> Void
    let onMoveWords: (Int) -> Void
    let onDropTargetChange: (DropPlacement, Bool) -> Void

    private var gapPlacement: DropPlacement {
        .gap(flatIndex: flatIndex)
    }

    private var isDropTarget: Bool {
        dropPlacement == gapPlacement
    }

    var body: some View {
        Button(action: { onInsert(utteranceIndex, insertIndex) }) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isDropTarget ? Color.accentColor.opacity(0.2) : Color.clear)
                .overlay {
                    if isDropTarget {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.accentColor, lineWidth: 2)
                    }
                }
                .frame(width: 8, height: 20)
        }
        .buttonStyle(.plain)
        .help("Insert word")
        .dropDestination(for: WordDragPayload.self) { items, _ in
            guard editMode == .move, items.first != nil else { return false }
            onMoveWords(flatIndex)
            onDropTargetChange(gapPlacement, false)
            return true
        } isTargeted: { targeted in
            onDropTargetChange(gapPlacement, targeted)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    struct Cache {
        var subviewCount = 0
        var maxWidth: CGFloat = 0
        var positions: [CGPoint] = []
        var size: CGSize = .zero
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        arrange(proposal: proposal, subviews: subviews, cache: &cache)
        return cache.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        arrange(proposal: proposal, subviews: subviews, cache: &cache)
        for (index, position) in cache.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let maxWidth = proposal.width ?? .infinity
        if cache.subviewCount == subviews.count,
           cache.maxWidth == maxWidth,
           !cache.positions.isEmpty {
            return
        }

        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        cache.subviewCount = subviews.count
        cache.maxWidth = maxWidth
        cache.positions = positions
        cache.size = CGSize(width: maxWidth, height: y + rowHeight)
    }
}
