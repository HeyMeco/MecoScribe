import Foundation
import MecoScribeCore
import Testing

@testable import MecoScribeApp

@MainActor
struct TranscriptEditorModelTests {
    init() {
        Preferences.registerDefaults()
    }

    /// Three utterances: S1 "hello there friend", S2 "good morning", S1 "see you".
    private func makeResult() -> ScribeResult {
        func words(_ text: String, _ speaker: String, start: Double) -> [DiarizedWord] {
            text.split(separator: " ").enumerated().map { index, word in
                DiarizedWord(
                    word: String(word),
                    startTime: start + Double(index) * 0.5,
                    endTime: start + Double(index) * 0.5 + 0.4,
                    confidence: 0.9,
                    speakerId: speaker
                )
            }
        }
        let utterances = [
            TranscriptOperations.makeUtterance(speakerId: "speaker_0", words: words("hello there friend", "speaker_0", start: 0)),
            TranscriptOperations.makeUtterance(speakerId: "speaker_1", words: words("good morning", "speaker_1", start: 3)),
            TranscriptOperations.makeUtterance(speakerId: "speaker_0", words: words("see you", "speaker_0", start: 6)),
        ]
        return ScribeResult(
            audioFile: "meeting.wav",
            durationSeconds: 8,
            speakerCount: 2,
            utterances: utterances,
            speakerIds: ["speaker_0", "speaker_1"]
        )
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mecoscribe-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeProject() throws -> ProjectFile {
        let project = ProjectFile(directory: try makeDirectory(), baseName: "meeting")
        try MScribeFile.write(
            makeResult(),
            speakerNames: [:],
            audioPath: project.directory.appendingPathComponent("meeting.wav").path,
            to: project.url
        )
        return project
    }

    private func texts(_ model: TranscriptEditorModel) -> [String] {
        model.utterances.map { "\($0.speakerId): \($0.text)" }
    }

    @Test func loadsProject() throws {
        let model = try TranscriptEditorModel(project: makeProject())
        #expect(texts(model) == ["speaker_0: hello there friend", "speaker_1: good morning", "speaker_0: see you"])
        #expect(model.totalWords == 7)
        #expect(model.flatStarts == [0, 3, 5])
        #expect(model.audioURL == nil)
    }

    @Test func assignSelectionRegroupsAndUndoes() throws {
        let model = try TranscriptEditorModel(project: makeProject())
        model.assign([3, 4], to: "speaker_0")
        #expect(texts(model) == ["speaker_0: hello there friend good morning see you"])
        model.undo()
        #expect(texts(model).count == 3)
        model.redo()
        #expect(texts(model).count == 1)
        // Assigning to the current speaker is a no-op without a history entry.
        model.undo()
        model.assign([0], to: "speaker_0")
        #expect(!model.canUndo)
    }

    @Test func moveWordsKeepsTimings() throws {
        let model = try TranscriptEditorModel(project: makeProject())
        // Move "friend" (flat 2) to right after "good" (target flat 4) as speaker_1.
        let friend = model.word(at: 2)!
        let moved = TranscriptOperations.moveWords(in: model.utterances, sourceIndices: [2], to: 4, speakerId: "speaker_1")
        #expect(moved?.map(\.text) == ["hello there", "good friend morning", "see you"])
        #expect(moved?[1].words[1].startTime == friend.startTime)
        // Dropping a word right where it already is changes nothing.
        #expect(TranscriptOperations.moveWords(in: model.utterances, sourceIndices: [2], to: 3, speakerId: "speaker_0") == nil)
    }

    @Test func enteringDragModeMergesAdjacentSameSpeaker() throws {
        let model = try TranscriptEditorModel(project: makeProject())
        model.deleteWords([3, 4]) // leaves two adjacent speaker_0 lines
        model.setEditMode(.drag)
        #expect(model.editMode == .drag)
        #expect(texts(model) == ["speaker_0: hello there friend see you"])
        model.undo()
        #expect(texts(model).count == 2)
    }

    @Test func wordEditingSplitsAndDeletes() throws {
        let model = try TranscriptEditorModel(project: makeProject())
        model.startWordEdit(1)
        #expect(model.editDraft == "there")
        model.editDraft = "over there"
        model.commitEdit()
        #expect(model.utterances[0].text == "hello over there friend")
        #expect(model.totalWords == 8)

        model.startWordEdit(0)
        model.editDraft = "   "
        model.commitEdit()
        #expect(model.utterances[0].text == "over there friend")

        model.undo()
        model.undo()
        #expect(model.utterances[0].text == "hello there friend")
    }

    @Test func cancelledInsertionLeavesNoTrace() throws {
        let model = try TranscriptEditorModel(project: makeProject())
        model.insertWord(row: 1, at: 1)
        #expect(model.editing == .word(flat: 4, isNew: true))
        #expect(model.totalWords == 8)
        model.cancelEdit()
        #expect(model.totalWords == 7)
        #expect(!model.canUndo)

        model.insertWord(row: 1, at: 2)
        model.editDraft = "everyone"
        model.commitEdit()
        #expect(model.utterances[1].text == "good morning everyone")
        model.undo()
        #expect(model.utterances[1].text == "good morning")
    }

    @Test func clickingAnotherWordCommitsAndAdjustsIndices() throws {
        let model = try TranscriptEditorModel(project: makeProject())
        model.startWordEdit(0)
        model.editDraft = ""          // deleting "hello" shifts later words left
        model.clickWord(5)            // was "see" before the commit
        #expect(model.editing == .word(flat: 4, isNew: false))
        #expect(model.editDraft == "see")
    }

    @Test func lineEditReconcilesTimings() throws {
        let model = try TranscriptEditorModel(project: makeProject())
        let original = model.utterances[1].words
        model.startLineEdit(1)
        model.editDraft = "good sunny morning"
        model.commitEdit()
        let words = model.utterances[1].words
        #expect(words.map(\.word) == ["good", "sunny", "morning"])
        #expect(words[0].startTime == original[0].startTime)
        #expect(words[2].startTime == original[1].startTime)
    }

    @Test func speakerManagement() throws {
        let model = try TranscriptEditorModel(project: makeProject())
        model.renameSpeaker("speaker_0", to: "Alice")
        #expect(model.speakerName("speaker_0") == "Alice")

        model.addSpeaker(named: "Carol", assigning: [6])
        #expect(model.speakerIds == ["speaker_0", "speaker_1", "speaker_2"])
        #expect(model.utterances.last?.speakerId == "speaker_2")
        #expect(model.utterances.last?.text == "you")

        // A speaker with lines cannot be deleted.
        model.deleteSpeaker("speaker_1")
        #expect(model.speakerIds.contains("speaker_1"))

        model.mergeSpeaker("speaker_1", into: "speaker_0")
        #expect(model.speakerIds == ["speaker_0", "speaker_2"])
        #expect(texts(model) == ["speaker_0: hello there friend good morning see", "speaker_2: you"])

        model.addSpeaker(named: "Empty", assigning: [])
        model.deleteSpeaker("speaker_3")
        #expect(model.speakerIds == ["speaker_0", "speaker_2"])
    }

    @Test func savesAndRoundTrips() throws {
        let project = try makeProject()
        let model = try TranscriptEditorModel(project: project)
        model.renameSpeaker("speaker_1", to: "Bob")
        model.setEditMode(.drag)
        model.assign([0], to: "speaker_1")
        model.saveNow()
        #expect(!model.isDirty)

        let entries = try ZipArchive.read(contentsOf: project.url)
        let text = String(decoding: try #require(entries["transcript.txt"]), as: UTF8.self)
        #expect(text.contains("] Bob:\nhello\n"))
        #expect(entries["transcript.html"].map { String(decoding: $0, as: UTF8.self).contains("Bob") } == true)
        let manifest = try JSONSerialization.jsonObject(with: try #require(entries["manifest.json"])) as? [String: Any]
        #expect(manifest?["schemaVersion"] as? String == "1.0")
        #expect(manifest?["format"] as? String == "mecoscribe")

        let reopened = try TranscriptEditorModel(project: project)
        #expect(reopened.utterances == model.utterances)
        #expect(reopened.speakerName("speaker_1") == "Bob")
    }

    @Test func readsViewerWhenTextAndTimingsAreMissing() throws {
        let project = try makeProject()
        var entries = try ZipArchive.read(contentsOf: project.url)
        entries["transcript.txt"] = nil
        entries["transcript.mecoscribe.json"] = nil
        // Finder's Compress wraps everything in a folder.
        try ZipArchive.write(entries.map { .init(name: "meeting/" + $0.key, data: $0.value) }, to: project.url)
        let model = try TranscriptEditorModel(project: project)
        #expect(texts(model) == ["speaker_0: hello there friend", "speaker_1: good morning", "speaker_0: see you"])
    }

    @Test func rejectsNewerSchema() throws {
        let project = try makeProject()
        var entries = try ZipArchive.read(contentsOf: project.url)
        let manifest = String(decoding: try #require(entries["manifest.json"]), as: UTF8.self)
            .replacingOccurrences(of: "\"1.0\"", with: "\"2.0\"")
        entries["manifest.json"] = Data(manifest.utf8)
        try ZipArchive.write(entries.map { .init(name: $0.key, data: $0.value) }, to: project.url)
        #expect(throws: MScribeError.self) { try TranscriptEditorModel(project: project) }
    }

    @Test func importsLegacyFilesAndClosesProject() throws {
        let directory = try makeDirectory()
        let legacy = LegacyTranscriptFiles(directory: directory, baseName: "meeting")
        try TextExporter.export(makeResult(), speakerNames: ["speaker_1": "Bob"], to: legacy.txtURL.path)
        try TimingsSidecar.write(
            TimingsSidecar(result: makeResult(), speakerNames: ["speaker_1": "Bob"]),
            to: legacy.sidecarURL.path
        )
        try Data().write(to: directory.appendingPathComponent("meeting.wav"))

        let workspace = Workspace()
        workspace.open(legacy.txtURL)
        let editor = try #require(workspace.editor)
        #expect(editor.project.url == legacy.project.url)
        #expect(legacy.project.exists)
        #expect(editor.speakerName("speaker_1") == "Bob")
        #expect(editor.audioURL?.lastPathComponent == "meeting.wav")
        #expect(FileManager.default.fileExists(atPath: legacy.txtURL.path))

        workspace.closeProject()
        #expect(workspace.isIdle)
        #expect(workspace.editor == nil)
    }

    @Test func zipHandlesEmptyAndCompressibleEntries() throws {
        let big = Data(String(repeating: "word ", count: 5000).utf8)
        let data = try ZipArchive.data(for: [.init(name: "empty.txt", data: Data()), .init(name: "dir/big.txt", data: big)])
        #expect(data.count < big.count)
        let entries = try ZipArchive.read(data)
        #expect(entries["empty.txt"] == Data())
        #expect(entries["dir/big.txt"] == big)
    }

    @Test func detectsExternalChangesAndReloads() async throws {
        let project = try makeProject()
        let model = try TranscriptEditorModel(project: project)
        var entries = try ZipArchive.read(contentsOf: project.url)
        let text = String(decoding: try #require(entries["transcript.txt"]), as: UTF8.self)
            .replacingOccurrences(of: "good morning", with: "good evening")
        entries["transcript.txt"] = Data(text.utf8)
        try await Task.sleep(for: .milliseconds(1100)) // ensure a new modification date
        try ZipArchive.write(entries.map { .init(name: $0.key, data: $0.value) }, to: project.url)
        model.pollForExternalChanges()
        #expect(model.externalChangeText != nil)
        model.reloadFromDisk()
        #expect(model.utterances[1].text == "good evening")
        #expect(model.externalChangeText == nil)
        #expect(!model.canUndo)
    }

    @Test func discardRestoresOpeningState() throws {
        let model = try TranscriptEditorModel(project: makeProject())
        model.assign([3, 4], to: "speaker_0")
        model.renameSpeaker("speaker_0", to: "Alice")
        #expect(model.hasEditsSinceOpening)
        model.discardEdits()
        #expect(!model.hasEditsSinceOpening)
        model.undo()
        #expect(model.speakerName("speaker_0") == "Alice")
    }

    @Test func deleteSelectedWords() throws {
        let model = try TranscriptEditorModel(project: makeProject())
        model.deleteWords([3, 4])
        #expect(texts(model) == ["speaker_0: hello there friend", "speaker_0: see you"])
    }
}

/// Interaction tests that need word positions, which normally come from layout.
@MainActor
struct TranscriptInteractionTests {
    init() {
        Preferences.registerDefaults()
    }

    /// Lays each utterance out on its own 20 pt line, words 50 pt apart.
    private func layOut(_ model: TranscriptEditorModel) {
        let frames = model.frames
        for (row, utterance) in model.utterances.enumerated() {
            frames.visibleRows.insert(row)
            frames.containerFrames[row] = CGRect(x: 0, y: CGFloat(row) * 40, width: 500, height: 20)
            frames.wordRects[row] = utterance.words.indices.map { CGRect(x: CGFloat($0) * 50, y: 0, width: 40, height: 20) }
        }
    }

    private func makeModel() throws -> TranscriptEditorModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mecoscribe-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let words = ["one", "two", "three"].enumerated().map { index, word in
            DiarizedWord(word: word, startTime: Double(index), endTime: Double(index) + 0.5, confidence: 1, speakerId: "speaker_0")
        }
        let more = ["four", "five"].enumerated().map { index, word in
            DiarizedWord(word: word, startTime: 5 + Double(index), endTime: 5.5 + Double(index), confidence: 1, speakerId: "speaker_1")
        }
        let result = ScribeResult(
            audioFile: "a.wav",
            durationSeconds: 7,
            speakerCount: 2,
            utterances: [
                TranscriptOperations.makeUtterance(speakerId: "speaker_0", words: words),
                TranscriptOperations.makeUtterance(speakerId: "speaker_1", words: more),
            ],
            speakerIds: ["speaker_0", "speaker_1"]
        )
        let project = ProjectFile(directory: directory, baseName: "a")
        try MScribeFile.write(result, speakerNames: [:], audioPath: directory.appendingPathComponent("a.wav").path, to: project.url)
        let model = try TranscriptEditorModel(project: project)
        layOut(model)
        return model
    }

    @Test func dragSelectsWordsAndOpensAssignMenu() throws {
        let model = try makeModel()
        model.dragChanged(start: CGPoint(x: 10, y: 10), location: CGPoint(x: 60, y: 10))
        model.dragChanged(start: CGPoint(x: 10, y: 10), location: CGPoint(x: 110, y: 10))
        model.dragEnded(location: CGPoint(x: 110, y: 10))
        #expect(model.selection == [0, 1, 2])
        #expect(model.assignMenuRect != nil)
    }

    @Test func dragWhileEditingCommitsAndSelects() throws {
        let model = try makeModel()
        model.startWordEdit(4)
        model.editDraft = "FIVE"
        // Starts on "one", outside the open editor.
        model.dragChanged(start: CGPoint(x: 10, y: 10), location: CGPoint(x: 30, y: 10))
        layOut(model) // committing the edit re-lays out the transcript
        model.dragChanged(start: CGPoint(x: 10, y: 10), location: CGPoint(x: 60, y: 10))
        model.dragEnded(location: CGPoint(x: 60, y: 10))
        #expect(model.editing == nil)
        #expect(model.utterances[1].text == "four FIVE")
        #expect(model.selection == [0, 1])
        #expect(model.assignMenuRect != nil)
    }

    @Test func dragInsideOpenEditorIsLeftToTheTextField() throws {
        let model = try makeModel()
        model.startWordEdit(1)
        model.dragChanged(start: CGPoint(x: 55, y: 10), location: CGPoint(x: 85, y: 10))
        model.dragEnded(location: CGPoint(x: 85, y: 10))
        #expect(model.editing == .word(flat: 1, isNew: false))
        #expect(model.selection.isEmpty)
    }

    @Test func detectsPlayingLineScrolledOutOfView() throws {
        let model = try makeModel()
        let frames = model.frames
        // Row 1 spans y 40–60 in content coordinates; the viewport is 30 pt tall.
        #expect(TranscriptView.offscreenEdge(row: 1, frames: frames, contentMinY: 0, viewportHeight: 30) == .bottom)
        #expect(TranscriptView.offscreenEdge(row: 1, frames: frames, contentMinY: -35, viewportHeight: 30) == nil)
        #expect(TranscriptView.offscreenEdge(row: 0, frames: frames, contentMinY: -35, viewportHeight: 30) == .top)
        #expect(TranscriptView.offscreenEdge(row: nil, frames: frames, contentMinY: 0, viewportHeight: 30) == nil)
        // A row the lazy stack has not built is off screen on the side it lies.
        frames.visibleRows = [1]
        #expect(TranscriptView.offscreenEdge(row: 0, frames: frames, contentMinY: 0, viewportHeight: 30) == .top)
    }
}
