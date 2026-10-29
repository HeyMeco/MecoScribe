import AppKit
import MecoScribeCore
import SwiftUI

private let transcriptSpace = "transcript"
private let viewportSpace = "transcriptViewport"

/// Scroll position bookkeeping. Not observable: it changes on every scroll frame, and
/// only the derived "is the playing line off screen" state should re-render.
@MainActor
private final class ScrollTracker {
    var viewportHeight: CGFloat = 0
    var contentMinY: CGFloat = 0
}

struct TranscriptView: View {
    let model: TranscriptEditorModel
    @AppStorage(Preferences.followPlayback) private var followPlayback = false
    @AppStorage(Preferences.transcriptFontSize) private var fontSize = 15.0
    @State private var tracker = ScrollTracker()
    /// Where the playing line is when it is scrolled out of view; nil while visible.
    @State private var offscreenActiveEdge: VerticalEdge?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVStack(alignment: .leading, spacing: model.editMode == .drag ? 4 : 10) {
                        ForEach(model.utterances.indices, id: \.self) { index in
                            row(index)
                                .id(index)
                                .onAppear { model.frames.visibleRows.insert(index) }
                                .onDisappear { model.frames.visibleRows.remove(index) }
                        }
                    }
                    .coordinateSpace(.named(transcriptSpace))
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.frame(in: .named(viewportSpace)).minY
                    } action: { minY in
                        tracker.contentMinY = minY
                        updateActiveVisibility()
                    }
                    .overlay(alignment: .topLeading) {
                        TranscriptOverlay(model: model)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.clickBackground() }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .named(transcriptSpace))
                            .onChanged { value in
                                model.dragChanged(start: value.startLocation, location: value.location)
                            }
                            .onEnded { value in
                                model.dragEnded(location: value.location)
                            }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: 1000, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .coordinateSpace(.named(viewportSpace))
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                tracker.viewportHeight = height
                updateActiveVisibility()
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .topTrailing) {
                if let edge = offscreenActiveEdge, let row = model.activeUtterances.min() {
                    JumpBackButton(
                        speakerName: model.speakerName(model.utterances[row].speakerId),
                        color: SpeakerPalette.color(model.speakerIndex(model.utterances[row].speakerId)),
                        edge: edge
                    ) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(row, anchor: UnitPoint(x: 0.5, y: 0.3))
                        }
                    }
                    .padding(12)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: offscreenActiveEdge)
            .onChange(of: model.activeUtterances.min()) { _, row in
                updateActiveVisibility()
                guard followPlayback, model.player.isPlaying, model.editing == nil, let row else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(row, anchor: UnitPoint(x: 0.5, y: 0.3))
                }
            }
        }
    }

    /// Recomputes whether the playing line is scrolled out of view, and on which side.
    private func updateActiveVisibility() {
        let edge = Self.offscreenEdge(
            row: model.activeUtterances.min(),
            frames: model.frames,
            contentMinY: tracker.contentMinY,
            viewportHeight: tracker.viewportHeight
        )
        if edge != offscreenActiveEdge { offscreenActiveEdge = edge }
    }

    static func offscreenEdge(
        row: Int?,
        frames: TranscriptFrames,
        contentMinY: CGFloat,
        viewportHeight: CGFloat
    ) -> VerticalEdge? {
        guard let row, viewportHeight > 0 else { return nil }
        guard frames.visibleRows.contains(row), let rect = frames.containerFrames[row] else {
            // Not materialized by the lazy stack, so certainly off screen.
            guard let first = frames.visibleRows.min() else { return nil }
            return row < first ? .top : .bottom
        }
        let top = rect.minY + contentMinY
        let bottom = rect.maxY + contentMinY
        if bottom < 0 { return .top }
        if top > viewportHeight { return .bottom }
        return nil
    }

    private var hint: String {
        var parts = [
            "Click a word to edit",
            "⌥-click to play from a word",
            "Right-click for more",
            "Click between words to add one",
            "Double-click a line to edit all of it",
        ]
        parts.append(model.editMode == .assign ? "Drag across words to reassign the speaker" : "Drag words to move them")
        parts.append("Space plays/pauses · Esc cancels")
        return parts.joined(separator: " · ")
    }

    private func row(_ index: Int) -> some View {
        let utterance = model.utterances[index]
        let start = model.flatStarts[index]
        let end = start + utterance.words.count

        var editingWord: Int?
        if case .word(let flat, _) = model.editing, flat >= start, flat < end {
            editingWord = flat - start
        }

        return UtteranceRow(
            model: model,
            index: index,
            utterance: utterance,
            flatStart: start,
            speakerName: model.speakerName(utterance.speakerId),
            color: SpeakerPalette.color(model.speakerIndex(utterance.speakerId)),
            isActive: model.activeUtterances.contains(index),
            activeWords: Self.local(model.activeWords, start, end),
            selectedWords: Self.local(model.selection, start, end),
            draggedWords: Self.local(model.draggedWords, start, end),
            editingWord: editingWord,
            isEditingLine: model.editing == .line(utterance: index),
            isDragMode: model.editMode == .drag,
            fontSize: fontSize
        )
        .equatable()
    }

    private static func local(_ indices: Set<Int>, _ start: Int, _ end: Int) -> Set<Int> {
        guard !indices.isEmpty else { return [] }
        var result = Set<Int>()
        for index in indices where index >= start && index < end {
            result.insert(index - start)
        }
        return result
    }
}

/// Floats over the transcript while the playing line is scrolled out of view.
private struct JumpBackButton: View {
    let speakerName: String
    let color: Color
    let edge: VerticalEdge
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: edge == .top ? "arrow.up" : "arrow.down")
                    .font(.caption.weight(.bold))
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text("Jump Back")
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(isHovering ? 0.25 : 0.12)))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .scaleEffect(isHovering ? 1.04 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help("Scroll back to the line being played (\(speakerName))")
        .accessibilityLabel("Jump back to the line being played, \(speakerName)")
    }
}

/// Drop indicator, drag label and the assign-speaker popover, drawn over the rows.
private struct TranscriptOverlay: View {
    let model: TranscriptEditorModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            if let target = model.dropTarget {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor)
                    .frame(width: target.indicator.width, height: target.indicator.height + 4)
                    .offset(x: target.indicator.minX, y: target.indicator.minY - 2)
            }

            if let location = model.dragLocation, !model.draggedWords.isEmpty {
                Text(dragLabel)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.6)))
                    .shadow(radius: 3, y: 1)
                    .offset(x: location.x + 14, y: location.y + 10)
            }

            if let rect = model.assignMenuRect {
                Color.clear
                    .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                    .popover(
                        isPresented: Binding(
                            get: { model.assignMenuRect != nil },
                            set: { if !$0 { model.dismissAssignMenu() } }
                        ),
                        arrowEdge: .bottom
                    ) {
                        AssignSpeakerMenu(model: model)
                    }
                    .padding(.leading, rect.minX)
                    .padding(.top, rect.minY)
            }
        }
        .allowsHitTesting(false)
    }

    private var dragLabel: String {
        let count = model.draggedWords.count
        if count == 1, let flat = model.draggedWords.first, let word = model.word(at: flat) {
            return word.word
        }
        return "\(count) words"
    }
}

// MARK: - Rows

private struct UtteranceRow: View, Equatable {
    let model: TranscriptEditorModel
    let index: Int
    let utterance: DiarizedUtterance
    let flatStart: Int
    let speakerName: String
    let color: Color
    let isActive: Bool
    let activeWords: Set<Int>
    let selectedWords: Set<Int>
    let draggedWords: Set<Int>
    let editingWord: Int?
    let isEditingLine: Bool
    let isDragMode: Bool
    let fontSize: Double

    nonisolated static func == (lhs: UtteranceRow, rhs: UtteranceRow) -> Bool {
        lhs.index == rhs.index
            && lhs.flatStart == rhs.flatStart
            && lhs.speakerName == rhs.speakerName
            && lhs.color == rhs.color
            && lhs.isActive == rhs.isActive
            && lhs.activeWords == rhs.activeWords
            && lhs.selectedWords == rhs.selectedWords
            && lhs.draggedWords == rhs.draggedWords
            && lhs.editingWord == rhs.editingWord
            && lhs.isEditingLine == rhs.isEditingLine
            && lhs.isDragMode == rhs.isDragMode
            && lhs.fontSize == rhs.fontSize
            && lhs.utterance == rhs.utterance
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                header
                if isEditingLine {
                    LineEditor(model: model, fontSize: fontSize)
                } else {
                    wordFlow
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, isDragMode ? 6 : 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? color.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isActive ? color.opacity(0.55) : Color(nsColor: .separatorColor).opacity(0.5))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.startLineEdit(index) }
        .contextMenu {
            Button("Play from Here") { model.play(fromUtterance: index) }
            Button("Edit Whole Line") { model.startLineEdit(index) }
            Divider()
            speakerMenu(title: "Change Speaker of Line")
        }
    }

    private var lineWords: Set<Int> {
        Set(flatStart..<(flatStart + utterance.words.count))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Menu {
                speakerMenuItems(for: lineWords)
            } label: {
                Text(speakerName)
                    .font(.system(size: fontSize - 2, weight: .semibold))
                    .foregroundStyle(color)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Change the speaker of this line")

            Button {
                model.play(fromUtterance: index)
            } label: {
                Text(TextExporter.formatTime(utterance.startTime))
                    .font(.system(size: fontSize - 3).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Play from here")

            Spacer()

            Button {
                model.startLineEdit(index)
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Edit the whole line (or double-click it)")
        }
    }

    private var wordFlow: some View {
        WordFlowLayout(row: index, frames: model.frames) {
            InsertGap(model: model, row: index, insertIndex: 0, height: fontSize * 1.35)
            ForEach(Array(utterance.words.enumerated()), id: \.offset) { wordIndex, word in
                Group {
                    if editingWord == wordIndex {
                        WordEditor(model: model, fontSize: fontSize)
                    } else {
                        WordChip(
                            model: model,
                            row: index,
                            wordIndex: wordIndex,
                            flat: flatStart + wordIndex,
                            word: word,
                            isActive: activeWords.contains(wordIndex),
                            isSelected: selectedWords.contains(wordIndex),
                            isDragged: draggedWords.contains(wordIndex),
                            isDragMode: isDragMode,
                            fontSize: fontSize
                        )
                    }
                }
                .layoutValue(key: WordIndexKey.self, value: wordIndex)
                InsertGap(model: model, row: index, insertIndex: wordIndex + 1, height: fontSize * 1.35)
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(transcriptSpace))
        } action: { [frames = model.frames, index] rect in
            frames.containerFrames[index] = rect
        }
    }

    private func speakerMenu(title: String) -> some View {
        Menu(title) {
            speakerMenuItems(for: lineWords)
        }
    }

    @ViewBuilder
    private func speakerMenuItems(for words: Set<Int>) -> some View {
        ForEach(model.speakerIds, id: \.self) { id in
            Button {
                model.assign(words, to: id)
            } label: {
                if id == utterance.speakerId {
                    Label(model.speakerName(id), systemImage: "checkmark")
                } else {
                    Text(model.speakerName(id))
                }
            }
            .disabled(id == utterance.speakerId)
        }
        Divider()
        Button("Add Speaker…") { model.requestAddSpeaker(assigning: words) }
    }
}

// MARK: - Words

private struct WordIndexKey: LayoutValueKey {
    static let defaultValue: Int? = nil
}

/// Flows words like text and records each word's rect for drag hit-testing.
/// Lines only break before words, so the insert gap after a word stays with it.
private struct WordFlowLayout: Layout {
    let row: Int
    let frames: TranscriptFrames
    var lineSpacing: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let result = arrange(width: width, subviews: subviews)
        return CGSize(width: width.isFinite ? width : result.size.width, height: result.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        var wordRects: [CGRect] = []
        for (index, subview) in subviews.enumerated() {
            let rect = result.rects[index]
            subview.place(
                at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                proposal: ProposedViewSize(rect.size)
            )
            if let word = subview[WordIndexKey.self] {
                if wordRects.count <= word {
                    wordRects.append(contentsOf: Array(repeating: .null, count: word - wordRects.count + 1))
                }
                wordRects[word] = rect
            }
        }
        let row = row
        let frames = frames
        MainActor.assumeIsolated {
            frames.wordRects[row] = wordRects
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (rects: [CGRect], size: CGSize) {
        var rects = Array(repeating: CGRect.zero, count: subviews.count)
        var lineStart = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        func finishLine(upTo end: Int) {
            for index in lineStart..<end {
                rects[index].origin.y = y + (lineHeight - rects[index].height) / 2
            }
            y += lineHeight + lineSpacing
            maxWidth = max(maxWidth, x)
            x = 0
            lineHeight = 0
            lineStart = end
        }

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let isWord = subview[WordIndexKey.self] != nil
            if isWord, x > 0, x + size.width > width {
                finishLine(upTo: index)
            }
            rects[index] = CGRect(origin: CGPoint(x: x, y: 0), size: size)
            x += size.width
            lineHeight = max(lineHeight, size.height)
        }
        if lineStart < subviews.count {
            finishLine(upTo: subviews.count)
        }
        return (rects, CGSize(width: maxWidth, height: max(y - lineSpacing, 0)))
    }
}

private struct WordChip: View {
    let model: TranscriptEditorModel
    let row: Int
    let wordIndex: Int
    let flat: Int
    let word: DiarizedWord
    let isActive: Bool
    let isSelected: Bool
    let isDragged: Bool
    let isDragMode: Bool
    let fontSize: Double
    @State private var isHovering = false

    var body: some View {
        Text(word.word)
            .font(.system(size: fontSize))
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(fill))
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor.opacity(0.7))
                }
            }
            .opacity(isDragged ? 0.35 : 1)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onTapGesture { model.clickWord(flat) }
            .help(tooltip)
            .contextMenu { menu }
    }

    private var fill: Color {
        if isSelected { return Color.accentColor.opacity(0.35) }
        if isActive { return Color.accentColor.opacity(0.22) }
        if isHovering { return Color.primary.opacity(0.08) }
        return .clear
    }

    private var tooltip: String {
        let action = isDragMode ? "Drag to move" : "Drag across words to reassign"
        return "\(TextExporter.formatTime(word.startTime)) · Click to edit · ⌥-click to play · \(action)"
    }

    @ViewBuilder
    private var menu: some View {
        Button("Play from Here") { model.play(fromFlat: flat) }
        Divider()
        Button("Edit Word") { model.startWordEdit(flat) }
        Button("Insert Word Before") { model.insertWord(row: row, at: wordIndex) }
        Button("Insert Word After") { model.insertWord(row: row, at: wordIndex + 1) }
        Button("Edit Whole Line") { model.startLineEdit(row) }
        Divider()
        Menu("Assign to Speaker") {
            ForEach(model.speakerIds, id: \.self) { id in
                Button(model.speakerName(id)) {
                    model.assign(model.targetWords(for: flat), to: id)
                }
            }
            Divider()
            Button("Add Speaker…") {
                model.requestAddSpeaker(assigning: model.targetWords(for: flat))
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            model.deleteWords(model.targetWords(for: flat))
        }
    }
}

/// The clickable space between words: click to insert a new word there.
private struct InsertGap: View {
    let model: TranscriptEditorModel
    let row: Int
    let insertIndex: Int
    let height: CGFloat
    @State private var isHovering = false

    var body: some View {
        Color.clear
            .frame(width: 6, height: height)
            .overlay {
                if isHovering {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.7))
                        .frame(width: 2)
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onTapGesture { model.insertWord(row: row, at: insertIndex) }
            .help("Click to add a word")
    }
}

private struct WordEditor: View {
    @Bindable var model: TranscriptEditorModel
    let fontSize: Double
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $model.editDraft)
            .textFieldStyle(.plain)
            .font(.system(size: fontSize))
            .frame(width: width)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 1.5))
            .focused($focused)
            .onSubmit { model.commitEdit() }
            .onAppear { focused = true }
    }

    private var width: CGFloat {
        let text = model.editDraft.isEmpty ? "word" : model.editDraft
        let measured = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: fontSize)]).width
        return max(28, ceil(measured) + 10)
    }
}

private struct LineEditor: View {
    @Bindable var model: TranscriptEditorModel
    let fontSize: Double
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("", text: $model.editDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize))
                .lineLimit(1...20)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 1.5))
                .focused($focused)
                .onSubmit { model.commitEdit() }
                .onAppear { focused = true }
            HStack {
                Text("Return saves · ⌥Return adds a line break · Esc cancels · word timings are kept where words match")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.cancelEdit() }
                Button("Save") { model.commitEdit() }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Assign menu

private struct AssignSpeakerMenu: View {
    let model: TranscriptEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.selection.count == 1 ? "Assign 1 word to" : "Assign \(model.selection.count) words to")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            ForEach(Array(model.speakerIds.enumerated()), id: \.element) { position, id in
                let isCurrent = model.selectionAlreadyBelongs(to: id)
                Button {
                    model.assignSelection(to: id)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(SpeakerPalette.color(position))
                            .frame(width: 10, height: 10)
                        Text(model.speakerName(id))
                        Spacer(minLength: 16)
                        if isCurrent {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        } else if position < 9 {
                            Text("\(position + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(MenuRowButtonStyle())
                .disabled(isCurrent)
            }
            Divider()
                .padding(.vertical, 4)
            Button {
                model.requestAddSpeaker(assigning: model.selection)
            } label: {
                Label("Add Speaker…", systemImage: "plus")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MenuRowButtonStyle())
        }
        .padding(8)
        .frame(minWidth: 220)
    }
}

private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor.opacity(isEnabled && (isHovering || configuration.isPressed) ? 0.2 : 0))
                )
                .opacity(isEnabled ? 1 : 0.55)
                .onHover { isHovering = $0 }
        }
    }
}
