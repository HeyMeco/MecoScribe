import Foundation
import MecoScribeCore

/// The editable part of a transcript; one undo/redo history entry.
struct TranscriptSnapshot: Equatable {
    var utterances: [DiarizedUtterance]
    var speakerIds: [String]
    var speakerNames: [String: String]
}

/// Pure transcript transformations, ported from the HTML viewer's editing logic.
/// Word positions are "flat indices": the word's position when all utterances are
/// concatenated in display order.
enum TranscriptOperations {
    static let utteranceGapSeconds: TimeInterval = 1.5

    static func makeUtterance(speakerId: String, words: [DiarizedWord]) -> DiarizedUtterance {
        DiarizedUtterance(
            speakerId: speakerId,
            startTime: words.first?.startTime ?? 0,
            endTime: words.last?.endTime ?? 0,
            text: words.map(\.word).joined(separator: " "),
            words: words
        )
    }

    /// Groups consecutive words into utterances, splitting on speaker changes and,
    /// optionally, on pauses longer than `utteranceGapSeconds`.
    static func regroup(_ words: [DiarizedWord], respectTimeGaps: Bool) -> [DiarizedUtterance] {
        guard let first = words.first else { return [] }
        var grouped: [DiarizedUtterance] = []
        var currentSpeaker = first.speakerId
        var currentWords: [DiarizedWord] = [first]

        for word in words.dropFirst() {
            let gap = word.startTime - currentWords[currentWords.count - 1].endTime
            if word.speakerId != currentSpeaker || (respectTimeGaps && gap > utteranceGapSeconds) {
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

    /// All words in display order, each tagged with its utterance's speaker.
    static func flatWords(_ utterances: [DiarizedUtterance]) -> [DiarizedWord] {
        utterances.flatMap { utterance in
            utterance.words.map { word in
                var word = word
                word.speakerId = utterance.speakerId
                return word
            }
        }
    }

    /// Makes word speakers match their utterance, rebuilds text from words, and drops
    /// empty utterances, so every later operation can rely on those invariants.
    static func normalized(_ utterances: [DiarizedUtterance]) -> [DiarizedUtterance] {
        utterances.compactMap { utterance in
            let words = utterance.words
                .filter { !$0.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { word -> DiarizedWord in
                    var word = word
                    word.speakerId = utterance.speakerId
                    return word
                }
            guard !words.isEmpty else { return nil }
            return makeUtterance(speakerId: utterance.speakerId, words: words)
        }
    }

    /// Moves the words at `sourceIndices` so they start at `targetFlatIndex` (an index
    /// into the current flat word list) and assigns them to `targetSpeakerId`.
    /// Returns nil when the move would not change anything.
    static func moveWords(
        in utterances: [DiarizedUtterance],
        sourceIndices: [Int],
        to targetFlatIndex: Int,
        speakerId targetSpeakerId: String
    ) -> [DiarizedUtterance]? {
        let words = flatWords(utterances)
        let sources = Array(Set(sourceIndices.filter { words.indices.contains($0) })).sorted()
        guard let minSource = sources.first, let maxSource = sources.last else { return nil }

        let movingSpeakers = Set(sources.map { words[$0].speakerId })
        let changesSpeaker = movingSpeakers.count != 1 || !movingSpeakers.contains(targetSpeakerId)
        if !changesSpeaker && targetFlatIndex >= minSource && targetFlatIndex <= maxSource + 1 {
            return nil
        }

        var adjustedTarget = targetFlatIndex
        for source in sources where source < targetFlatIndex {
            adjustedTarget -= 1
        }

        let movingSet = Set(sources)
        let moving = sources.map { index -> DiarizedWord in
            var word = words[index]
            word.speakerId = targetSpeakerId
            return word
        }
        var remaining = words.enumerated().filter { !movingSet.contains($0.offset) }.map(\.element)
        adjustedTarget = max(0, min(adjustedTarget, remaining.count))
        remaining.insert(contentsOf: moving, at: adjustedTarget)

        return regroup(remaining, respectTimeGaps: false)
    }

    /// Assigns the given words to a speaker. Returns nil if they already belong to it.
    static func assignWords(
        in utterances: [DiarizedUtterance],
        indices: Set<Int>,
        to speakerId: String
    ) -> [DiarizedUtterance]? {
        var words = flatWords(utterances)
        let valid = indices.filter { words.indices.contains($0) }
        guard !valid.isEmpty, !valid.allSatisfy({ words[$0].speakerId == speakerId }) else {
            return nil
        }
        for index in valid {
            words[index].speakerId = speakerId
        }
        return regroup(words, respectTimeGaps: false)
    }

    /// Reassigns every word of `sourceId` to `targetId`.
    static func replaceSpeaker(
        in utterances: [DiarizedUtterance],
        source sourceId: String,
        target targetId: String
    ) -> [DiarizedUtterance] {
        let words = flatWords(utterances).map { word -> DiarizedWord in
            var word = word
            if word.speakerId == sourceId {
                word.speakerId = targetId
            }
            return word
        }
        return regroup(words, respectTimeGaps: false)
    }

    /// Joins neighbouring utterances that share a speaker. Returns nil if none do.
    static func mergeAdjacentSameSpeaker(_ utterances: [DiarizedUtterance]) -> [DiarizedUtterance]? {
        let merged = regroup(flatWords(utterances), respectTimeGaps: false)
        return merged.count == utterances.count ? nil : merged
    }

    static func nextSpeakerId(after speakerIds: [String]) -> String {
        var maxIndex = -1
        for id in speakerIds {
            if id.hasPrefix("speaker_"), let number = Int(id.dropFirst("speaker_".count)) {
                maxIndex = max(maxIndex, number)
            }
        }
        return "speaker_\(maxIndex + 1)"
    }

    /// Splits an edited word that now contains spaces into several words, dividing the
    /// original timing evenly between them.
    static func split(_ word: DiarizedWord, into tokens: [String]) -> [DiarizedWord] {
        guard tokens.count > 1 else {
            var word = word
            word.word = tokens.first ?? ""
            return [word]
        }
        let duration = max(word.endTime - word.startTime, 0.01)
        let step = duration / Double(tokens.count)
        return tokens.enumerated().map { index, token in
            DiarizedWord(
                word: token,
                startTime: word.startTime + step * Double(index),
                endTime: index == tokens.count - 1 ? word.endTime : word.startTime + step * Double(index + 1),
                confidence: word.confidence,
                speakerId: word.speakerId
            )
        }
    }

    static func tokens(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
