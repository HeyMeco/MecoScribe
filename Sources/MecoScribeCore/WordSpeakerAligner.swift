import FluidAudio
import Foundation

enum WordSpeakerAligner {
    static func align(
        words: [WordTiming],
        segments: [TimedSpeakerSegment]
    ) -> [DiarizedUtterance] {
        guard !words.isEmpty else { return [] }

        let sortedSegments = segments.sorted { $0.startTimeSeconds < $1.startTimeSeconds }
        var diarizedWords: [DiarizedWord] = []

        for word in words {
            let midpoint = (word.startTime + word.endTime) / 2
            let speakerId = speakerForTime(
                midpoint,
                segments: sortedSegments,
                fallback: diarizedWords.last?.speakerId ?? sortedSegments.first?.speakerId ?? "speaker_0"
            )

            diarizedWords.append(
                DiarizedWord(
                    word: word.word,
                    startTime: word.startTime,
                    endTime: word.endTime,
                    confidence: word.confidence,
                    speakerId: speakerId
                ))
        }

        return groupIntoUtterances(diarizedWords)
    }

    private static func speakerForTime(
        _ time: TimeInterval,
        segments: [TimedSpeakerSegment],
        fallback: String
    ) -> String {
        var bestSpeaker = fallback
        var bestOverlap: Float = -1

        for segment in segments {
            let overlapStart = max(Float(time), segment.startTimeSeconds)
            let overlapEnd = min(Float(time), segment.endTimeSeconds)
            let overlap = max(0, overlapEnd - overlapStart)

            if overlap > bestOverlap {
                bestOverlap = overlap
                bestSpeaker = segment.speakerId
            }
        }

        if bestOverlap <= 0 {
            var nearestDistance = Float.greatestFiniteMagnitude
            for segment in segments {
                let distance: Float
                if Float(time) < segment.startTimeSeconds {
                    distance = segment.startTimeSeconds - Float(time)
                } else if Float(time) > segment.endTimeSeconds {
                    distance = Float(time) - segment.endTimeSeconds
                } else {
                    return segment.speakerId
                }

                if distance < nearestDistance {
                    nearestDistance = distance
                    bestSpeaker = segment.speakerId
                }
            }
        }

        return bestSpeaker
    }

    private static func groupIntoUtterances(_ words: [DiarizedWord]) -> [DiarizedUtterance] {
        guard !words.isEmpty else { return [] }

        var utterances: [DiarizedUtterance] = []
        var currentSpeaker = words[0].speakerId
        var currentWords: [DiarizedWord] = [words[0]]

        for word in words.dropFirst() {
            if word.speakerId != currentSpeaker {
                utterances.append(makeUtterance(speakerId: currentSpeaker, words: currentWords))
                currentSpeaker = word.speakerId
                currentWords = [word]
            } else {
                currentWords.append(word)
            }
        }

        utterances.append(makeUtterance(speakerId: currentSpeaker, words: currentWords))
        return utterances
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
}
