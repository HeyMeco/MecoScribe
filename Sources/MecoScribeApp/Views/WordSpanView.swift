import MecoScribeCore
import SwiftUI
import UniformTypeIdentifiers

enum DropPlacement: Equatable {
    case gap(flatIndex: Int)
    case wordBefore(flatIndex: Int)
    case wordAfter(flatIndex: Int)
}

@MainActor
struct WordSpanView: View, Equatable {
    let word: DiarizedWord
    let ref: WordRef
    let speakerColor: Color
    let isActive: Bool
    let isSelected: Bool
    let isEditing: Bool
    let editMode: EditorEditMode
    let flatIndex: Int
    let dropPlacement: DropPlacement?
    let isDraggingSelection: Bool
    let onTap: () -> Void
    let onEdit: (String) -> Void
    let onBeginEdit: () -> Void
    let onDragStart: () -> Void
    let onDrop: (Int) -> Void
    let onSeek: () -> Void
    let onSelectionDragStart: () -> Void
    let onSelectionDragEnter: () -> Void
    let onSelectionDragEnd: () -> Void
    let onDropTargetChange: (DropPlacement, Bool) -> Void

    nonisolated static func == (lhs: WordSpanView, rhs: WordSpanView) -> Bool {
        lhs.word == rhs.word
            && lhs.ref == rhs.ref
            && lhs.isActive == rhs.isActive
            && lhs.isSelected == rhs.isSelected
            && lhs.isEditing == rhs.isEditing
            && lhs.editMode == rhs.editMode
            && lhs.flatIndex == rhs.flatIndex
            && lhs.dropPlacement == rhs.dropPlacement
            && lhs.isDraggingSelection == rhs.isDraggingSelection
    }

    var body: some View {
        Group {
            if isEditing {
                WordEditField(word: word.word, onEdit: onEdit)
            } else {
                wordLabel
            }
        }
    }

    private var wordLabel: some View {
        Text(word.word + " ")
            .font(.body)
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? speakerColor : .clear, lineWidth: 2)
            }
            .overlay(alignment: .leading) {
                if dropPlacement == .wordBefore(flatIndex: flatIndex) {
                    dropIndicatorBar
                }
            }
            .overlay(alignment: .trailing) {
                if dropPlacement == .wordAfter(flatIndex: flatIndex + 1) {
                    dropIndicatorBar
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 1, perform: onTap)
            .onTapGesture(count: 2) {
                onBeginEdit()
            }
            .contextMenu {
                Button("Play from here", action: onSeek)
                Button("Edit word", action: onBeginEdit)
            }
            .modifier(WordInteractionModifier(
                editMode: editMode,
                payload: WordDragPayload(flatIndex: flatIndex, speakerId: word.speakerId),
                word: word.word,
                flatIndex: flatIndex,
                isDraggingSelection: isDraggingSelection,
                onDragStart: onDragStart,
                onDropBefore: { onDrop(flatIndex) },
                onDropAfter: { onDrop(flatIndex + 1) },
                onDropTargetChange: onDropTargetChange,
                onSelectionDragStart: onSelectionDragStart,
                onSelectionDragEnter: onSelectionDragEnter,
                onSelectionDragEnd: onSelectionDragEnd
            ))
    }

    private var dropIndicatorBar: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2)
            .padding(.vertical, 1)
    }

    private var backgroundColor: Color {
        if isActive { return speakerColor.opacity(0.25) }
        if isSelected { return speakerColor.opacity(0.12) }
        return .clear
    }
}

private struct WordEditField: View {
    let word: String
    let onEdit: (String) -> Void
    @State private var editText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("word", text: $editText)
            .textFieldStyle(.plain)
            .font(.body)
            .focused($isFocused)
            .onSubmit { onEdit(editText) }
            .onExitCommand { onEdit(word) }
            .onAppear {
                editText = word
                isFocused = true
            }
            .frame(minWidth: 40)
    }
}

private struct WordInteractionModifier: ViewModifier {
    let editMode: EditorEditMode
    let payload: WordDragPayload
    let word: String
    let flatIndex: Int
    let isDraggingSelection: Bool
    let onDragStart: () -> Void
    let onDropBefore: () -> Void
    let onDropAfter: () -> Void
    let onDropTargetChange: (DropPlacement, Bool) -> Void
    let onSelectionDragStart: () -> Void
    let onSelectionDragEnter: () -> Void
    let onSelectionDragEnd: () -> Void

    func body(content: Content) -> some View {
        if editMode == .move {
            content
                .overlay {
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .dropDestination(for: WordDragPayload.self) { items, _ in
                                guard items.first != nil else { return false }
                                onDropBefore()
                                onDropTargetChange(.wordBefore(flatIndex: flatIndex), false)
                                return true
                            } isTargeted: { targeted in
                                onDropTargetChange(.wordBefore(flatIndex: flatIndex), targeted)
                            }
                        Color.clear
                            .contentShape(Rectangle())
                            .dropDestination(for: WordDragPayload.self) { items, _ in
                                guard items.first != nil else { return false }
                                onDropAfter()
                                onDropTargetChange(.wordAfter(flatIndex: flatIndex + 1), false)
                                return true
                            } isTargeted: { targeted in
                                onDropTargetChange(.wordAfter(flatIndex: flatIndex + 1), targeted)
                            }
                    }
                }
                .draggable(payload) {
                    Text(word)
                        .padding(6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .onAppear(perform: onDragStart)
                }
        } else {
            content
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { _ in onSelectionDragStart() }
                        .onEnded { _ in onSelectionDragEnd() }
                )
                .onContinuousHover { phase in
                    guard isDraggingSelection else { return }
                    if case .active = phase {
                        onSelectionDragEnter()
                    }
                }
        }
    }
}

struct WordDragPayload: Codable, Transferable, Hashable {
    let flatIndex: Int
    let speakerId: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
