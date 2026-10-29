import FluidAudio
import Foundation

enum WordTimingMerger {
    static func mergeTokensIntoWords(_ tokenTimings: [TokenTiming]) -> [WordTiming] {
        guard !tokenTimings.isEmpty else { return [] }

        var wordTimings: [WordTiming] = []
        var currentWord = ""
        var currentStartTime: TimeInterval?
        var currentEndTime: TimeInterval = 0
        var currentConfidences: [Float] = []

        for timing in tokenTimings {
            let token = timing.token
            if token.isEmpty || token == "<blank>" || token == "<pad>" {
                continue
            }

            let startsNewWord = isWordBoundary(token)
            if startsNewWord {
                if !currentWord.isEmpty, let startTime = currentStartTime {
                    wordTimings.append(
                        WordTiming(
                            word: currentWord,
                            startTime: startTime,
                            endTime: currentEndTime,
                            confidence: averageConfidence(currentConfidences)
                        ))
                }

                currentWord = stripWordBoundaryPrefix(token)
                currentStartTime = timing.startTime
                currentEndTime = timing.endTime
                currentConfidences = [timing.confidence]
            } else {
                if currentStartTime == nil {
                    currentStartTime = timing.startTime
                }
                currentWord += token
                currentEndTime = timing.endTime
                currentConfidences.append(timing.confidence)
            }
        }

        if !currentWord.isEmpty, let startTime = currentStartTime {
            wordTimings.append(
                WordTiming(
                    word: currentWord,
                    startTime: startTime,
                    endTime: currentEndTime,
                    confidence: averageConfidence(currentConfidences)
                ))
        }

        return wordTimings
    }

    private static func averageConfidence(_ confidences: [Float]) -> Float {
        confidences.isEmpty ? 0.0 : confidences.reduce(0, +) / Float(confidences.count)
    }

    /// SentencePiece word starts use `▁`; Parakeet token timings use a leading space.
    private static func isWordBoundary(_ token: String) -> Bool {
        token.hasPrefix(" ") || token.hasPrefix("\n") || token.hasPrefix("\t") || token.hasPrefix("\u{2581}")
    }

    private static func stripWordBoundaryPrefix(_ token: String) -> String {
        if token.hasPrefix("\u{2581}") {
            return String(token.dropFirst())
        }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
