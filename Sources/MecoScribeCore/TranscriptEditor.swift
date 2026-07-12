import Foundation

public enum SpeakerPalette {
    static let colors: [String] = [
        "#4F8EF7",
        "#E85D75",
        "#2ECC71",
        "#F39C12",
        "#9B59B6",
        "#1ABC9C",
        "#E67E22",
        "#3498DB",
        "#E74C3C",
        "#16A085",
    ]

    public static func color(for speakerId: String, speakerIds: [String]) -> String {
        guard let index = speakerIds.firstIndex(of: speakerId) else {
            return colors[0]
        }
        return colors[index % colors.count]
    }

    public static func displayName(for speakerId: String, speakerNames: [String: String]) -> String {
        if let name = speakerNames[speakerId], !name.isEmpty {
            return name
        }
        if speakerId.hasPrefix("speaker_") {
            let suffix = speakerId.dropFirst("speaker_".count)
            if let number = Int(suffix) {
                return "Speaker \(number + 1)"
            }
        }
        return speakerId
    }
}

public enum TranscriptFormatting {
    static let utteranceGapSeconds: TimeInterval = 1.5

    public static func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

public struct WordRef: Hashable, Sendable {
    public let utteranceIndex: Int
    public let wordIndex: Int

    public init(utteranceIndex: Int, wordIndex: Int) {
        self.utteranceIndex = utteranceIndex
        self.wordIndex = wordIndex
    }
}

public struct TranscriptState: Sendable, Equatable {
    public var utterances: [DiarizedUtterance]
    public var speakerIds: [String]
    public var speakerNames: [String: String]
    public var audioFile: String
    public var durationSeconds: TimeInterval

    public init(result: ScribeResult, speakerNames: [String: String]) {
        utterances = result.utterances
        speakerIds = result.speakerIds
        self.speakerNames = speakerNames
        audioFile = result.audioFile
        durationSeconds = result.durationSeconds
    }

    public func buildResult() -> ScribeResult {
        ScribeResult(
            audioFile: audioFile,
            durationSeconds: durationSeconds,
            speakerCount: speakerIds.count,
            utterances: utterances,
            speakerIds: speakerIds
        )
    }

    public func transcriptionCount(for speakerId: String) -> Int {
        utterances.reduce(0) { count, utterance in
            count + utterance.words.filter { $0.speakerId == speakerId }.count
        }
    }
}

public enum TranscriptEditor {
    public static func flattenWords(_ utterances: [DiarizedUtterance]) -> [DiarizedWord] {
        utterances.flatMap(\.words)
    }

    public static func regroupUtterances(
        from words: [DiarizedWord],
        respectTimeGaps: Bool = true
    ) -> [DiarizedUtterance] {
        guard !words.isEmpty else { return [] }

        var grouped: [DiarizedUtterance] = []
        var currentSpeaker = words[0].speakerId
        var currentWords: [DiarizedWord] = [words[0]]

        for word in words.dropFirst() {
            let gap = word.startTime - currentWords.last!.endTime
            let speakerChanged = word.speakerId != currentSpeaker
            if speakerChanged || (respectTimeGaps && gap > TranscriptFormatting.utteranceGapSeconds) {
                grouped.append(makeUtterance(speakerId: currentSpeaker, words: currentWords))
                currentSpeaker = word.speakerId
                currentWords = [word]
            } else {
                currentWords.append(word)
            }
        }

        grouped.append(makeUtterance(speakerId: currentSpeaker, words: currentWords))
        return grouped
    }

    public static func assignWords(
        _ refs: [WordRef],
        toSpeaker speakerId: String,
        in state: TranscriptState
    ) -> TranscriptState? {
        guard !refs.isEmpty else { return nil }

        let refSet = Set(refs.map { "\($0.utteranceIndex):\($0.wordIndex)" })
        var allWords: [DiarizedWord] = []

        for (utteranceIndex, utterance) in state.utterances.enumerated() {
            for (wordIndex, word) in utterance.words.enumerated() {
                var nextWord = word
                if refSet.contains("\(utteranceIndex):\(wordIndex)") {
                    nextWord = DiarizedWord(
                        word: word.word,
                        startTime: word.startTime,
                        endTime: word.endTime,
                        confidence: word.confidence,
                        speakerId: speakerId
                    )
                }
                allWords.append(nextWord)
            }
        }

        if refs.allSatisfy({ state.utterances[$0.utteranceIndex].words[$0.wordIndex].speakerId == speakerId }) {
            return nil
        }

        var updated = state
        updated.utterances = regroupUtterances(from: allWords, respectTimeGaps: false)
        updated.speakerIds = mergeSpeakerIds(state.speakerIds, with: [speakerId])
        return updated
    }

    public static func moveWords(
        _ refs: [WordRef],
        toFlatIndex targetFlatIndex: Int,
        speakerId targetSpeakerId: String,
        in state: TranscriptState
    ) -> TranscriptState? {
        guard !refs.isEmpty else { return nil }

        let items = flattenWordsWithIndices(state.utterances)
        let sourceIndices = refs
            .map { flatIndex(utteranceIndex: $0.utteranceIndex, wordIndex: $0.wordIndex, utterances: state.utterances) }
            .sorted()

        guard !sourceIndices.isEmpty else { return nil }

        let minSource = sourceIndices[0]
        let maxSource = sourceIndices[sourceIndices.count - 1]
        let movingSpeakerIds = Set(sourceIndices.map { items[$0].word.speakerId })
        let changesSpeaker = movingSpeakerIds.count != 1 || !movingSpeakerIds.contains(targetSpeakerId)

        if !changesSpeaker && targetFlatIndex >= minSource && targetFlatIndex <= maxSource + 1 {
            return nil
        }

        var adjustedTarget = targetFlatIndex
        for sourceIndex in sourceIndices where sourceIndex < targetFlatIndex {
            adjustedTarget -= 1
        }

        let movingSet = Set(sourceIndices)
        let movingWords = sourceIndices.map { items[$0].word }
        var remaining = items.filter { !movingSet.contains($0.flatIndex) }.map(\.word)

        let inserted = movingWords.map { word in
            DiarizedWord(
                word: word.word,
                startTime: word.startTime,
                endTime: word.endTime,
                confidence: word.confidence,
                speakerId: targetSpeakerId
            )
        }

        let safeIndex = min(max(adjustedTarget, 0), remaining.count)
        remaining.insert(contentsOf: inserted, at: safeIndex)

        var updated = state
        updated.utterances = regroupUtterances(from: remaining, respectTimeGaps: false)
        updated.speakerIds = mergeSpeakerIds(state.speakerIds, with: [targetSpeakerId])
        return updated
    }

    public static func editWord(
        utteranceIndex: Int,
        wordIndex: Int,
        newText: String,
        in state: TranscriptState
    ) -> TranscriptState? {
        guard state.utterances.indices.contains(utteranceIndex),
              state.utterances[utteranceIndex].words.indices.contains(wordIndex)
        else { return nil }

        var updated = state
        let utterance = updated.utterances[utteranceIndex]
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            var words = utterance.words
            words.remove(at: wordIndex)
            if words.isEmpty {
                updated.utterances.remove(at: utteranceIndex)
                return updated
            }
            updated.utterances[utteranceIndex] = makeUtterance(speakerId: utterance.speakerId, words: words)
            return updated
        }

        let oldWord = utterance.words[wordIndex]
        var words = utterance.words
        words[wordIndex] = DiarizedWord(
            word: trimmed,
            startTime: oldWord.startTime,
            endTime: oldWord.endTime,
            confidence: oldWord.confidence,
            speakerId: oldWord.speakerId
        )
        updated.utterances[utteranceIndex] = makeUtterance(speakerId: utterance.speakerId, words: words)
        return updated
    }

    public static func editUtterance(
        utteranceIndex: Int,
        newText: String,
        in state: TranscriptState
    ) -> TranscriptState? {
        guard state.utterances.indices.contains(utteranceIndex) else { return nil }

        var updated = state
        let utterance = updated.utterances[utteranceIndex]
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            updated.utterances.remove(at: utteranceIndex)
            return updated
        }

        let words = WordTimingReconciler.reconcile(
            text: trimmed,
            speakerId: utterance.speakerId,
            startTime: utterance.startTime,
            endTime: utterance.endTime,
            templateWords: utterance.words
        )

        updated.utterances[utteranceIndex] = DiarizedUtterance(
            speakerId: utterance.speakerId,
            startTime: words.first?.startTime ?? utterance.startTime,
            endTime: words.last?.endTime ?? utterance.endTime,
            text: trimmed,
            words: words
        )
        return updated
    }

    public static func insertWord(
        utteranceIndex: Int,
        insertIndex: Int,
        in state: TranscriptState
    ) -> (state: TranscriptState, editRef: WordRef)? {
        guard state.utterances.indices.contains(utteranceIndex) else { return nil }

        var updated = state
        let utterance = updated.utterances[utteranceIndex]
        var words = utterance.words

        let newWord: DiarizedWord
        if words.isEmpty {
            newWord = DiarizedWord(
                word: "",
                startTime: utterance.startTime,
                endTime: max(utterance.endTime, utterance.startTime + 0.01),
                confidence: 1,
                speakerId: utterance.speakerId
            )
            words.append(newWord)
        } else {
            let refIndex = min(insertIndex, words.count - 1)
            let reference = words[refIndex]
            newWord = DiarizedWord(
                word: "",
                startTime: reference.startTime,
                endTime: reference.endTime,
                confidence: reference.confidence,
                speakerId: reference.speakerId
            )
            let safeInsert = min(max(insertIndex, 0), words.count)
            words.insert(newWord, at: safeInsert)
        }

        updated.utterances[utteranceIndex] = makeUtterance(speakerId: utterance.speakerId, words: words)
        let editIndex = min(max(insertIndex, 0), words.count - 1)
        return (updated, WordRef(utteranceIndex: utteranceIndex, wordIndex: editIndex))
    }

    public static func renameSpeaker(
        _ speakerId: String,
        to name: String,
        in state: TranscriptState
    ) -> TranscriptState {
        var updated = state
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            updated.speakerNames.removeValue(forKey: speakerId)
        } else {
            updated.speakerNames[speakerId] = trimmed
        }
        return updated
    }

    public static func addSpeaker(in state: TranscriptState, name: String? = nil) -> (state: TranscriptState, speakerId: String) {
        var updated = state
        let speakerId = "speaker_\(updated.speakerIds.count)"
        updated.speakerIds.append(speakerId)
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.speakerNames[speakerId] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (updated, speakerId)
    }

    public static func deleteSpeaker(_ speakerId: String, in state: TranscriptState) -> TranscriptState? {
        guard state.transcriptionCount(for: speakerId) == 0 else { return nil }
        var updated = state
        updated.speakerIds.removeAll { $0 == speakerId }
        updated.speakerNames.removeValue(forKey: speakerId)
        return updated
    }

    public static func flatIndex(utteranceIndex: Int, wordIndex: Int, utterances: [DiarizedUtterance]) -> Int {
        var index = 0
        for u in 0..<utteranceIndex where u < utterances.count {
            index += utterances[u].words.count
        }
        return index + wordIndex
    }

    public static func wordRefs(
        inFlatRange range: ClosedRange<Int>,
        utterances: [DiarizedUtterance]
    ) -> Set<WordRef> {
        let lower = min(range.lowerBound, range.upperBound)
        let upper = max(range.lowerBound, range.upperBound)
        var refs: Set<WordRef> = []
        var flatIndex = 0

        for (utteranceIndex, utterance) in utterances.enumerated() {
            for wordIndex in utterance.words.indices {
                if flatIndex >= lower && flatIndex <= upper {
                    refs.insert(WordRef(utteranceIndex: utteranceIndex, wordIndex: wordIndex))
                }
                flatIndex += 1
            }
        }

        return refs
    }

    private static func flattenWordsWithIndices(_ utterances: [DiarizedUtterance]) -> [(flatIndex: Int, word: DiarizedWord)] {
        var items: [(flatIndex: Int, word: DiarizedWord)] = []
        var flatIndex = 0
        for utterance in utterances {
            for word in utterance.words {
                items.append((flatIndex, word))
                flatIndex += 1
            }
        }
        return items
    }

    private static func makeUtterance(speakerId: String, words: [DiarizedWord]) -> DiarizedUtterance {
        DiarizedUtterance(
            speakerId: speakerId,
            startTime: words.first!.startTime,
            endTime: words.last!.endTime,
            text: words.map(\.word).joined(separator: " "),
            words: words
        )
    }

    private static func mergeSpeakerIds(_ existing: [String], with additional: [String]) -> [String] {
        var merged = existing
        for id in additional where !merged.contains(id) {
            merged.append(id)
        }
        return merged
    }
}
