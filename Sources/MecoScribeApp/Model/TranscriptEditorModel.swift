import AppKit
import Foundation
import MecoScribeCore
import Observation

enum EditMode: String, CaseIterable, Identifiable {
    case assign
    case drag

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assign: return "Edit Mode"
        case .drag: return "Move Mode"
        }
    }

    var hint: String {
        switch self {
        case .assign: return "Click a word to edit it. Select words to reassign their speaker."
        case .drag: return "Drag words to move them. Their timings move with them."
        }
    }
}

enum EditingTarget: Equatable {
    case word(flat: Int, isNew: Bool)
    case line(utterance: Int)
}

enum SpeakerSheet: Identifiable, Equatable {
    case rename(String)
    case add(assigning: [Int])

    var id: String {
        switch self {
        case .rename(let speakerId): return "rename-\(speakerId)"
        case .add: return "add"
        }
    }
}

struct DropTarget: Equatable {
    var flatIndex: Int
    var speakerId: String
    var indicator: CGRect
}

/// One open transcript: its editable state, undo history, playback sync, and the
/// auto-save / external-change handling that the HTML viewer does with a linked folder.
@MainActor
@Observable
final class TranscriptEditorModel {
    static let maxHistory = 100

    let project: ProjectFile
    let player: AudioPlayerModel
    @ObservationIgnored let frames = TranscriptFrames()

    private(set) var sourceFile: String
    private(set) var durationSeconds: TimeInterval
    private(set) var audioURL: URL?
    @ObservationIgnored private var manifestAudio: MScribeManifest.Audio?
    @ObservationIgnored private var createdAt: Date?

    // MARK: Transcript state

    private(set) var utterances: [DiarizedUtterance] = []
    private(set) var speakerIds: [String] = []
    private(set) var speakerNames: [String: String] = [:]
    /// Flat index of the first word of each utterance.
    private(set) var flatStarts: [Int] = []
    private(set) var totalWords = 0
    @ObservationIgnored private var wordTimes: [(start: Double, end: Double)] = []
    @ObservationIgnored private var originalSnapshot: TranscriptSnapshot

    // MARK: History

    private var undoStack: [TranscriptSnapshot] = []
    private var redoStack: [TranscriptSnapshot] = []

    // MARK: Interaction state

    var editMode: EditMode = .assign
    private(set) var selection: Set<Int> = []
    @ObservationIgnored private var selectionAnchor: Int?
    private(set) var editing: EditingTarget?
    var editDraft = ""
    /// Where the "Assign to speaker" popover points, in transcript content coordinates.
    private(set) var assignMenuRect: CGRect?
    private(set) var dropTarget: DropTarget?
    private(set) var draggedWords: Set<Int> = []
    private(set) var dragLocation: CGPoint?
    @ObservationIgnored private var interaction: Interaction?
    /// Where the current drag began. SwiftUI can cancel a drag without reporting its
    /// end, so a different start point means a new drag and a stale one is dropped.
    @ObservationIgnored private var interactionStart: CGPoint?
    @ObservationIgnored private var lastDragEndedAt = Date.distantPast
    var speakerSheet: SpeakerSheet?
    var mergeSourceSpeaker: String?
    var deleteCandidateSpeaker: String?

    private(set) var activeWords: Set<Int> = []
    private(set) var activeUtterances: Set<Int> = []

    private enum Interaction {
        case selecting(anchor: Int)
        case moving(refs: [Int])
        case ignored
    }

    // MARK: Save state

    private(set) var isDirty = false
    private(set) var isSaving = false
    private(set) var savePending = false
    private(set) var lastSavedAt: Date?
    private(set) var saveError: String?
    /// Transcript text after another app changed the project file; drives the conflict banner.
    private(set) var externalChangeText: String?
    @ObservationIgnored private var lastWrittenText: String?
    @ObservationIgnored private var lastSeenModificationDate: Date?
    @ObservationIgnored private var lastWriteAt = Date.distantPast
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(project: ProjectFile) throws {
        let document = try MScribeFile.read(from: project.url)
        let parsed = document.transcript
        self.project = project
        manifestAudio = document.manifest.audio
        createdAt = document.manifest.createdAt
        sourceFile = parsed.result.audioFile
        durationSeconds = parsed.result.durationSeconds
        player = AudioPlayerModel(fallbackDuration: parsed.result.durationSeconds)
        originalSnapshot = TranscriptSnapshot(utterances: [], speakerIds: [], speakerNames: [:])

        let snapshot = Self.snapshot(from: parsed)
        apply(snapshot)
        originalSnapshot = snapshot
        lastWrittenText = document.transcriptText
        lastSeenModificationDate = Self.modificationDate(of: project.url)

        audioURL = ProjectLoader.resolveAudio(sourceFile: sourceFile, manifestAudio: manifestAudio, project: project)
        player.load(url: audioURL)
        player.onTimeChange = { [weak self] time in
            self?.updateActiveWords(at: time)
        }
        startPolling()
    }

    private static func snapshot(from parsed: ParsedTranscript) -> TranscriptSnapshot {
        let utterances = TranscriptOperations.normalized(parsed.result.utterances)
        var speakerIds = parsed.result.speakerIds
        for utterance in utterances where !speakerIds.contains(utterance.speakerId) {
            speakerIds.append(utterance.speakerId)
        }
        return TranscriptSnapshot(utterances: utterances, speakerIds: speakerIds, speakerNames: parsed.speakerNames)
    }

    /// Stops background work. Flushes a pending save first.
    func close() {
        if savePending || isDirty {
            closeActiveEditor(commit: true)
            saveNow()
        }
        pollTask?.cancel()
        pollTask = nil
        player.pause()
    }

    // MARK: Derived values

    var title: String { project.baseName }

    var snapshot: TranscriptSnapshot {
        TranscriptSnapshot(utterances: utterances, speakerIds: speakerIds, speakerNames: speakerNames)
    }

    func speakerName(_ id: String) -> String {
        speakerNames[id] ?? TextExporter.displayName(for: id)
    }

    func speakerIndex(_ id: String) -> Int {
        speakerIds.firstIndex(of: id) ?? 0
    }

    func utteranceCount(for speakerId: String) -> Int {
        utterances.filter { $0.speakerId == speakerId }.count
    }

    var canUndo: Bool { !undoStack.isEmpty && editing == nil }
    var canRedo: Bool { !redoStack.isEmpty && editing == nil }

    func word(at flat: Int) -> DiarizedWord? {
        guard let (row, word) = location(ofFlat: flat) else { return nil }
        return utterances[row].words[word]
    }

    func location(ofFlat flat: Int) -> (row: Int, word: Int)? {
        guard flat >= 0, flat < totalWords else { return nil }
        var low = 0
        var high = flatStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if flatStarts[mid] <= flat { low = mid } else { high = mid - 1 }
        }
        return (low, flat - flatStarts[low])
    }

    func flatIndex(row: Int, word: Int) -> Int {
        flatStarts[row] + word
    }

    func currentResult() -> ScribeResult {
        ScribeResult(
            audioFile: sourceFile,
            durationSeconds: durationSeconds,
            speakerCount: speakerIds.count,
            utterances: utterances,
            speakerIds: speakerIds
        )
    }

    func transcriptText() -> String {
        TextExporter.text(for: currentResult(), speakerNames: speakerNames)
    }

    // MARK: State application & history

    private func apply(_ snapshot: TranscriptSnapshot) {
        utterances = snapshot.utterances
        speakerIds = snapshot.speakerIds
        speakerNames = snapshot.speakerNames
        rebuildIndex()
    }

    private func rebuildIndex() {
        var starts: [Int] = []
        starts.reserveCapacity(utterances.count)
        var times: [(start: Double, end: Double)] = []
        var count = 0
        for utterance in utterances {
            starts.append(count)
            count += utterance.words.count
            for word in utterance.words {
                times.append((word.startTime, word.endTime))
            }
        }
        flatStarts = starts
        totalWords = count
        wordTimes = times
        // Keep recorded word positions: rows whose content changed are laid out again
        // and overwrite theirs, while unchanged rows are not re-rendered (they are
        // equatable) and would otherwise be left with none, breaking selection and
        // moving until the next full re-layout.
        frames.discardRows(from: utterances.count)
        updateActiveWords(at: player.currentTime)
    }

    /// Records the current state for undo, runs `change`, and keeps the entry only if
    /// `change` reports that it modified something.
    @discardableResult
    private func performChange(_ change: () -> Bool) -> Bool {
        let before = snapshot
        guard change() else { return false }
        undoStack.append(before)
        if undoStack.count > Self.maxHistory {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        rebuildIndex()
        clearTransientState()
        markDirty()
        return true
    }

    private func setUtterances(_ next: [DiarizedUtterance]?) -> Bool {
        guard let next else { return false }
        utterances = next
        return true
    }

    func undo() {
        guard canUndo, let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        apply(previous)
        clearTransientState()
        markDirty()
    }

    func redo() {
        guard canRedo, let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        apply(next)
        clearTransientState()
        markDirty()
    }

    private func clearTransientState() {
        selection.removeAll()
        selectionAnchor = nil
        assignMenuRect = nil
        dropTarget = nil
        draggedWords.removeAll()
        dragLocation = nil
        interaction = nil
        interactionStart = nil
    }

    // MARK: Playback sync

    private func updateActiveWords(at time: Double) {
        var words = Set<Int>()
        for (index, timing) in wordTimes.enumerated() where time >= timing.start && time <= timing.end + 0.05 {
            words.insert(index)
        }
        var rows = Set<Int>()
        for (index, utterance) in utterances.enumerated()
        where time >= utterance.startTime && time <= utterance.endTime + 0.15 {
            rows.insert(index)
        }
        if words != activeWords { activeWords = words }
        if rows != activeUtterances { activeUtterances = rows }
    }

    func play(fromFlat flat: Int) {
        guard let word = word(at: flat) else { return }
        player.play(from: word.startTime)
    }

    func play(fromUtterance index: Int) {
        guard utterances.indices.contains(index) else { return }
        player.play(from: utterances[index].startTime)
    }

    func locateAudio(_ url: URL) {
        audioURL = url
        AudioOverrides.set(url, for: project)
        player.load(url: url)
    }

    // MARK: Edit mode

    func setEditMode(_ mode: EditMode) {
        guard mode != editMode else { return }
        closeActiveEditor(commit: true)
        clearTransientState()
        editMode = mode
        if mode == .drag {
            // Moving words works across a single run of text per speaker turn.
            performChange { setUtterances(TranscriptOperations.mergeAdjacentSameSpeaker(utterances)) }
        }
    }

    // MARK: Word clicks & selection

    func clickWord(_ flat: Int) {
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.option) {
            play(fromFlat: flat)
            return
        }
        guard Date().timeIntervalSince(lastDragEndedAt) > 0.2 else { return }
        let flat = closeEditorAdjusting(flat)
        if modifiers.contains(.shift) {
            let anchor = selectionAnchor ?? selection.min() ?? flat
            selection = Set(min(anchor, flat)...max(anchor, flat))
            selectionAnchor = anchor
            selectionChanged(endingAt: flat)
        } else if modifiers.contains(.command) {
            if selection.contains(flat) {
                selection.remove(flat)
            } else {
                selection.insert(flat)
            }
            selectionAnchor = flat
            selectionChanged(endingAt: flat)
        } else {
            clearTransientState()
            startWordEdit(flat)
        }
    }

    private func selectionChanged(endingAt flat: Int) {
        guard editMode == .assign, !selection.isEmpty, let (row, word) = location(ofFlat: flat) else {
            assignMenuRect = nil
            return
        }
        assignMenuRect = frames.rect(row: row, word: word)
    }

    func clickBackground() {
        closeActiveEditor(commit: true)
        clearTransientState()
    }

    /// Esc: cancels an edit, else dismisses menus and selection. Returns whether it acted.
    @discardableResult
    func escape() -> Bool {
        if editing != nil {
            cancelEdit()
            return true
        }
        if assignMenuRect != nil || !selection.isEmpty {
            clearTransientState()
            return true
        }
        return false
    }

    /// Number keys 1–9 pick a speaker while the assign popover is open.
    func assignSelection(toSpeakerAt position: Int) -> Bool {
        guard assignMenuRect != nil, speakerIds.indices.contains(position) else { return false }
        let id = speakerIds[position]
        if !selectionAlreadyBelongs(to: id) { assignSelection(to: id) }
        return true
    }

    func dismissAssignMenu() {
        assignMenuRect = nil
    }

    func selectAll() {
        guard editing == nil, totalWords > 0 else { return }
        selection = Set(0..<totalWords)
        selectionAnchor = 0
    }

    // MARK: Mouse drags (range selection / moving words)

    func dragChanged(start: CGPoint, location: CGPoint) {
        if interaction != nil, start != interactionStart {
            resetDrag()
        }
        if interaction == nil {
            interactionStart = start
            // A drag inside the open text field selects text there; anywhere else it
            // commits the edit and selects (or moves) words.
            if dragStartsInsideEditor(start) {
                interaction = .ignored
                return
            }
            assignMenuRect = nil
            if editMode == .drag, let hit = frames.exactHit(at: start) {
                let flat = closeEditorAdjusting(flatIndex(row: hit.row, word: hit.word))
                let refs = selection.contains(flat) ? selection.sorted() : [flat]
                interaction = .moving(refs: refs)
                draggedWords = Set(refs)
            } else if let hit = frames.nearestHit(to: start) {
                let flat = closeEditorAdjusting(flatIndex(row: hit.row, word: hit.word))
                interaction = .selecting(anchor: flat)
                selectionAnchor = flat
            } else {
                interaction = .ignored
            }
        }

        switch interaction {
        case .selecting(let anchor):
            guard let hit = frames.nearestHit(to: location) else { return }
            let flat = flatIndex(row: hit.row, word: hit.word)
            let next = Set(min(anchor, flat)...max(anchor, flat))
            if next != selection { selection = next }
        case .moving:
            dragLocation = location
            dropTarget = dropTarget(at: location)
        case .ignored, nil:
            break
        }
    }

    private func dragStartsInsideEditor(_ point: CGPoint) -> Bool {
        switch editing {
        case .word(let flat, _):
            guard let (row, word) = location(ofFlat: flat), let rect = frames.rect(row: row, word: word) else {
                return false
            }
            return rect.insetBy(dx: -2, dy: -2).contains(point)
        case .line(let index):
            return frames.containerFrames[index]?.insetBy(dx: -8, dy: -8).contains(point) ?? false
        case nil:
            return false
        }
    }

    private func resetDrag() {
        interaction = nil
        interactionStart = nil
        dropTarget = nil
        draggedWords.removeAll()
        dragLocation = nil
    }

    func dragEnded(location: CGPoint) {
        defer {
            lastDragEndedAt = Date()
            resetDrag()
        }
        switch interaction {
        case .selecting:
            guard let hit = frames.nearestHit(to: location) else { return }
            selectionChanged(endingAt: flatIndex(row: hit.row, word: hit.word))
        case .moving(let refs):
            guard let target = dropTarget(at: location) else { return }
            let moved = performChange {
                setUtterances(
                    TranscriptOperations.moveWords(
                        in: utterances,
                        sourceIndices: refs,
                        to: target.flatIndex,
                        speakerId: target.speakerId
                    ))
            }
            if !moved {
                performChange { setUtterances(TranscriptOperations.mergeAdjacentSameSpeaker(utterances)) }
            }
        case .ignored, nil:
            break
        }
    }

    private func dropTarget(at point: CGPoint) -> DropTarget? {
        guard let hit = frames.nearestHit(to: point), utterances.indices.contains(hit.row) else { return nil }
        let insertAfter = point.x >= hit.rect.midX
        let flat = flatIndex(row: hit.row, word: hit.word) + (insertAfter ? 1 : 0)
        let x = insertAfter ? hit.rect.maxX + 1 : hit.rect.minX - 3
        return DropTarget(
            flatIndex: flat,
            speakerId: utterances[hit.row].speakerId,
            indicator: CGRect(x: x, y: hit.rect.minY, width: 2, height: hit.rect.height)
        )
    }

    // MARK: Speaker assignment

    func selectionAlreadyBelongs(to speakerId: String) -> Bool {
        !selection.isEmpty && selection.allSatisfy { word(at: $0)?.speakerId == speakerId }
    }

    func assignSelection(to speakerId: String) {
        assign(selection, to: speakerId)
    }

    func assign(_ indices: Set<Int>, to speakerId: String) {
        let indices = closeEditorAdjusting(indices)
        if !performChange({
            setUtterances(TranscriptOperations.assignWords(in: utterances, indices: indices, to: speakerId))
        }) {
            assignMenuRect = nil
        }
    }

    func assignUtterance(_ index: Int, to speakerId: String) {
        guard utterances.indices.contains(index) else { return }
        let start = flatStarts[index]
        assign(Set(start..<(start + utterances[index].words.count)), to: speakerId)
    }

    /// Words a context-menu action on `flat` applies to: the selection if the word is
    /// part of it, otherwise just that word.
    func targetWords(for flat: Int) -> Set<Int> {
        selection.contains(flat) ? selection : [flat]
    }

    // MARK: Speakers

    func requestAddSpeaker(assigning indices: Set<Int> = []) {
        assignMenuRect = nil
        speakerSheet = .add(assigning: indices.sorted())
    }

    var nextDefaultSpeakerName: String {
        TextExporter.displayName(for: TranscriptOperations.nextSpeakerId(after: speakerIds))
    }

    func addSpeaker(named name: String, assigning indices: [Int]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        performChange {
            let id = TranscriptOperations.nextSpeakerId(after: speakerIds)
            speakerIds.append(id)
            speakerNames[id] = trimmed
            if let assigned = TranscriptOperations.assignWords(in: utterances, indices: Set(indices), to: id) {
                utterances = assigned
            }
            return true
        }
    }

    func renameSpeaker(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != speakerName(id) else { return }
        performChange {
            speakerNames[id] = trimmed
            return true
        }
    }

    func deleteSpeaker(_ id: String) {
        guard utteranceCount(for: id) == 0, speakerIds.contains(id) else { return }
        performChange {
            speakerIds.removeAll { $0 == id }
            speakerNames[id] = nil
            return true
        }
    }

    func mergeSpeaker(_ sourceId: String, into targetId: String) {
        guard sourceId != targetId, speakerIds.contains(sourceId), speakerIds.contains(targetId) else { return }
        closeActiveEditor(commit: true)
        performChange {
            utterances = TranscriptOperations.replaceSpeaker(in: utterances, source: sourceId, target: targetId)
            speakerIds.removeAll { $0 == sourceId }
            speakerNames[sourceId] = nil
            return true
        }
    }

    // MARK: Text editing

    func startWordEdit(_ flat: Int) {
        let flat = closeEditorAdjusting(flat)
        guard let word = word(at: flat) else { return }
        editDraft = word.word
        editing = .word(flat: flat, isNew: false)
    }

    func startLineEdit(_ index: Int) {
        guard utterances.indices.contains(index) else { return }
        var index = index
        if editing != nil {
            let firstWord = closeEditorAdjusting(flatStarts[index])
            guard let location = location(ofFlat: firstWord) else { return }
            index = location.row
        }
        clearTransientState()
        editDraft = utterances[index].text
        editing = .line(utterance: index)
    }

    /// Inserts an empty word at `insertIndex` within utterance `row` and starts editing it.
    func insertWord(row: Int, at insertIndex: Int) {
        guard utterances.indices.contains(row), !utterances[row].words.isEmpty else { return }
        var row = row
        var insertIndex = insertIndex
        if editing != nil {
            // Anchor the gap to a neighbouring word so it survives the commit.
            let after = insertIndex > 0
            let anchor = closeEditorAdjusting(flatStarts[row] + (after ? insertIndex - 1 : insertIndex))
            guard let location = location(ofFlat: anchor) else { return }
            row = location.row
            insertIndex = location.word + (after ? 1 : 0)
        }
        clearTransientState()
        let words = utterances[row].words
        let reference = words[min(insertIndex, words.count - 1)]
        let newWord = DiarizedWord(
            word: "",
            startTime: reference.startTime,
            endTime: reference.endTime,
            confidence: reference.confidence,
            speakerId: utterances[row].speakerId
        )
        let before = snapshot
        utterances[row].words.insert(newWord, at: insertIndex)
        undoStack.append(before)
        if undoStack.count > Self.maxHistory { undoStack.removeFirst() }
        redoStack.removeAll()
        rebuildIndex()
        editDraft = ""
        editing = .word(flat: flatIndex(row: row, word: insertIndex), isNew: true)
    }

    /// Commits any open edit and maps `flat`, captured before the commit, to where that
    /// word is afterwards (an edit can add or remove words before it).
    private func closeEditorAdjusting(_ flat: Int) -> Int {
        guard let editing else { return flat }
        let pivot: Int
        switch editing {
        case .word(let editedFlat, _): pivot = editedFlat
        case .line(let index): pivot = flatStarts.indices.contains(index) ? flatStarts[index] : 0
        }
        let before = totalWords
        closeActiveEditor(commit: true)
        return flat > pivot ? flat + (totalWords - before) : flat
    }

    private func closeEditorAdjusting(_ indices: Set<Int>) -> Set<Int> {
        guard editing != nil else { return indices }
        let probe = indices.sorted()
        guard let first = probe.first else {
            closeActiveEditor(commit: true)
            return indices
        }
        let before = totalWords
        let pivot: Int
        switch editing {
        case .word(let editedFlat, _): pivot = editedFlat
        case .line(let index): pivot = flatStarts.indices.contains(index) ? flatStarts[index] : first
        case nil: pivot = first
        }
        closeActiveEditor(commit: true)
        let delta = totalWords - before
        return Set(probe.map { $0 > pivot ? $0 + delta : $0 })
    }

    func closeActiveEditor(commit: Bool) {
        guard editing != nil else { return }
        if commit { commitEdit() } else { cancelEdit() }
    }

    func commitEdit() {
        switch editing {
        case .word(let flat, let isNew):
            commitWordEdit(flat: flat, isNew: isNew)
        case .line(let index):
            commitLineEdit(index)
        case nil:
            break
        }
    }

    func cancelEdit() {
        guard let editing else { return }
        self.editing = nil
        if case .word(_, true) = editing, let previous = undoStack.popLast() {
            // Abandoning a freshly inserted word removes it again.
            apply(previous)
        }
    }

    private func commitWordEdit(flat: Int, isNew: Bool) {
        editing = nil
        guard let (row, wordIndex) = location(ofFlat: flat) else { return }
        let original = utterances[row].words[wordIndex]
        let tokens = TranscriptOperations.tokens(in: editDraft)

        if isNew {
            // The insertion already recorded an undo entry; fold the typed text into it.
            if tokens.isEmpty {
                if let previous = undoStack.popLast() { apply(previous) }
                return
            }
            utterances[row].words.replaceSubrange(
                wordIndex...wordIndex,
                with: TranscriptOperations.split(original, into: tokens)
            )
            utterances = TranscriptOperations.normalized(utterances)
            rebuildIndex()
            markDirty()
            return
        }

        guard tokens != [original.word] else { return }
        performChange {
            utterances[row].words.replaceSubrange(
                wordIndex...wordIndex,
                with: TranscriptOperations.split(original, into: tokens)
            )
            utterances = TranscriptOperations.normalized(utterances)
            return true
        }
    }

    private func commitLineEdit(_ index: Int) {
        editing = nil
        guard utterances.indices.contains(index) else { return }
        let next = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let utterance = utterances[index]
        guard TranscriptOperations.tokens(in: next) != TranscriptOperations.tokens(in: utterance.text) else { return }
        performChange {
            let words = WordTimingReconciler.reconcile(
                text: next,
                speakerId: utterance.speakerId,
                startTime: utterance.startTime,
                endTime: utterance.endTime,
                templateWords: utterance.words
            )
            utterances[index] = TranscriptOperations.makeUtterance(speakerId: utterance.speakerId, words: words)
            utterances = TranscriptOperations.normalized(utterances)
            return true
        }
    }

    func deleteWords(_ indices: Set<Int>) {
        let indices = closeEditorAdjusting(indices)
        guard !indices.isEmpty else { return }
        performChange {
            var flat = 0
            for row in utterances.indices {
                let count = utterances[row].words.count
                let local = indices.compactMap { index -> Int? in
                    index >= flat && index < flat + count ? index - flat : nil
                }
                for word in local.sorted(by: >) {
                    utterances[row].words.remove(at: word)
                }
                flat += count
            }
            utterances = TranscriptOperations.normalized(utterances)
            return true
        }
    }

    /// Restores the transcript as it was when it was opened (undoable).
    func discardEdits() {
        closeActiveEditor(commit: false)
        guard snapshot != originalSnapshot else { return }
        performChange {
            utterances = originalSnapshot.utterances
            speakerIds = originalSnapshot.speakerIds
            speakerNames = originalSnapshot.speakerNames
            return true
        }
    }

    var hasEditsSinceOpening: Bool { snapshot != originalSnapshot }

    // MARK: Saving

    private func markDirty() {
        isDirty = true
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        savePending = true
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            if self.editing != nil {
                self.scheduleSave()
                return
            }
            self.saveNow()
        }
    }

    /// "Sync now": commits any open edit and writes all transcript files immediately.
    func saveExplicitly() {
        closeActiveEditor(commit: true)
        saveNow()
        externalChangeText = nil
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        savePending = false
        isSaving = true
        defer { isSaving = false }

        let result = currentResult()
        do {
            try FileManager.default.createDirectory(at: project.directory, withIntermediateDirectories: true)
            try MScribeFile.write(
                result,
                speakerNames: speakerNames,
                audioPath: audioPathForSaving,
                to: project.url,
                generator: AppInfo.generator,
                createdAt: createdAt
            )
            if createdAt == nil { createdAt = Date() }
            lastWrittenText = TextExporter.text(for: result, speakerNames: speakerNames)
            lastSeenModificationDate = Self.modificationDate(of: project.url)
            lastWriteAt = Date()
            lastSavedAt = Date()
            isDirty = false
            saveError = nil
        } catch {
            saveError = "Could not save \(project.url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Absolute audio path recorded in the project (and linked from the HTML viewer).
    private var audioPathForSaving: String {
        if let audioURL { return audioURL.path }
        if let absolute = manifestAudio?.absolutePath, !absolute.isEmpty { return absolute }
        return ProjectLoader.absoluteSourcePath(sourceFile, in: project.directory)
    }

    func exportText(to url: URL) throws {
        closeActiveEditor(commit: true)
        try transcriptText().write(to: url, atomically: true, encoding: .utf8)
    }

    func exportHTML(to url: URL) throws {
        closeActiveEditor(commit: true)
        try HtmlExporter.export(
            currentResult(),
            audioPath: audioPathForSaving,
            htmlPath: url.path,
            speakerNames: speakerNames
        )
    }

    /// Writes the container's contents as loose CLI files (`<base>.txt`,
    /// `<base>.mecoscribe.json`, `<base>.html`) into `directory`. Returns the `.txt`.
    @discardableResult
    func exportSeparateFiles(to directory: URL) throws -> URL {
        closeActiveEditor(commit: true)
        let files = LegacyTranscriptFiles(directory: directory, baseName: project.baseName)
        let result = currentResult()
        try TextExporter.export(result, speakerNames: speakerNames, to: files.txtURL.path)
        try TimingsSidecar.write(TimingsSidecar(result: result, speakerNames: speakerNames), to: files.sidecarURL.path)
        try HtmlExporter.export(result, audioPath: audioPathForSaving, htmlPath: files.htmlURL.path, speakerNames: speakerNames)
        return files.txtURL
    }

    // MARK: External changes

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.pollForExternalChanges()
            }
        }
    }

    func pollForExternalChanges() {
        guard editing == nil, !isSaving, !savePending, !isDirty, externalChangeText == nil else { return }
        guard Date().timeIntervalSince(lastWriteAt) > 2 else { return }
        guard let modified = Self.modificationDate(of: project.url), modified != lastSeenModificationDate else {
            return
        }
        lastSeenModificationDate = modified
        guard let text = try? MScribeFile.read(from: project.url).transcriptText else { return }
        if Self.equivalent(text, lastWrittenText) || Self.equivalent(text, transcriptText()) {
            lastWrittenText = text
            return
        }
        externalChangeText = text
    }

    func reloadFromDisk() {
        closeActiveEditor(commit: false)
        do {
            let document = try MScribeFile.read(from: project.url)
            let snapshot = Self.snapshot(from: document.transcript)
            apply(snapshot)
            originalSnapshot = snapshot
            undoStack.removeAll()
            redoStack.removeAll()
            clearTransientState()
            manifestAudio = document.manifest.audio
            createdAt = document.manifest.createdAt
            lastWrittenText = document.transcriptText
            lastSeenModificationDate = Self.modificationDate(of: project.url)
            isDirty = false
            lastSavedAt = nil
            externalChangeText = nil
        } catch {
            saveError = "Could not reload: \(error.localizedDescription)"
        }
    }

    func keepLocalEdits() {
        externalChangeText = nil
        saveNow()
    }

    private static func equivalent(_ a: String, _ b: String?) -> Bool {
        guard let b else { return false }
        func normalize(_ text: String) -> String {
            text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return normalize(a) == normalize(b)
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
