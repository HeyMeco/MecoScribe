import Foundation

public struct TimingsSidecar: Codable, Sendable {
    public static let currentVersion = 1
    public static let fileExtension = "mecoscribe.json"

    let version: Int
    let audioFile: String
    let durationSeconds: TimeInterval
    let speakerCount: Int
    let speakerIds: [String]
    let speakerNames: [String: String]
    let utterances: [DiarizedUtterance]
    let words: [DiarizedWord]?

    public init(result: ScribeResult, speakerNames: [String: String]) {
        version = Self.currentVersion
        audioFile = result.audioFile
        durationSeconds = result.durationSeconds
        speakerCount = result.speakerCount
        speakerIds = result.speakerIds
        self.speakerNames = speakerNames
        utterances = result.utterances
        words = result.utterances.flatMap(\.words).sorted { $0.startTime < $1.startTime }
    }

    var result: ScribeResult {
        ScribeResult(
            audioFile: audioFile,
            durationSeconds: durationSeconds,
            speakerCount: speakerCount,
            utterances: utterances,
            speakerIds: speakerIds
        )
    }

    var canonicalWords: [DiarizedWord] {
        if let words, !words.isEmpty {
            return words.sorted { $0.startTime < $1.startTime }
        }
        return utterances.flatMap(\.words).sorted { $0.startTime < $1.startTime }
    }

    public static func path(forTxtPath txtPath: String) -> String {
        let base = (txtPath as NSString).deletingPathExtension
        return (base as NSString).appendingPathExtension(fileExtension)!
    }

    static func path(forHtmlPath htmlPath: String) -> String {
        path(forTxtPath: (htmlPath as NSString).deletingPathExtension + ".txt")
    }

    static func basename(forTxtPath txtPath: String) -> String {
        URL(fileURLWithPath: path(forTxtPath: txtPath)).lastPathComponent
    }

    public static func write(_ sidecar: TimingsSidecar, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sidecar)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    public static func read(from path: String) throws -> TimingsSidecar {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        return try decoder.decode(TimingsSidecar.self, from: data)
    }

    static func merge(
        txtPath: String,
        sidecar: TimingsSidecar,
        audioPath: String
    ) throws -> ParsedTranscript {
        let text = try String(contentsOfFile: txtPath, encoding: .utf8)

        if transcriptsEquivalent(text, transcriptText(from: sidecar)) {
            return ParsedTranscript(result: sidecar.result, speakerNames: sidecar.speakerNames)
        }

        let lines = text.components(separatedBy: .newlines)
        let segments = TranscriptParser.parseSegmentsPublic(from: lines)
        guard !segments.isEmpty else {
            throw TranscriptParserError.noSegments
        }

        var speakerIds = sidecar.speakerIds
        var speakerNames = sidecar.speakerNames
        var utterances: [DiarizedUtterance] = []
        let wordBank = sidecar.canonicalWords
        var bankCursor = 0

        for (index, segment) in segments.enumerated() {
            let speakerId = TranscriptParser.resolveSpeakerIdPublic(
                label: segment.speakerLabel,
                speakerIds: &speakerIds,
                speakerNames: &speakerNames
            )

            let templateSlice = Array(wordBank.dropFirst(bankCursor))
            let fallbackStart = segment.startTime
            let fallbackEnd: TimeInterval
            if index + 1 < segments.count {
                fallbackEnd = segments[index + 1].startTime
            } else {
                fallbackEnd = templateSlice.last?.endTime ?? max(fallbackStart + 1, sidecar.durationSeconds)
            }
            let startTime = templateSlice.first?.startTime ?? fallbackStart
            let endTime = templateSlice.last?.endTime ?? fallbackEnd

            let reconciled = WordTimingReconciler.reconcileWithConsumed(
                text: segment.text,
                speakerId: speakerId,
                startTime: startTime,
                endTime: endTime,
                templateWords: templateSlice
            )
            bankCursor += reconciled.consumed

            utterances.append(
                DiarizedUtterance(
                    speakerId: speakerId,
                    startTime: reconciled.words.first?.startTime ?? startTime,
                    endTime: reconciled.words.last?.endTime ?? endTime,
                    text: segment.text,
                    words: reconciled.words
                )
            )
        }

        var durationSeconds = sidecar.durationSeconds
        if durationSeconds <= 0, let last = utterances.last {
            durationSeconds = last.endTime
        }

        let result = ScribeResult(
            audioFile: sidecar.audioFile.isEmpty ? audioPath : sidecar.audioFile,
            durationSeconds: durationSeconds,
            speakerCount: max(sidecar.speakerCount, speakerIds.count),
            utterances: utterances,
            speakerIds: speakerIds
        )

        return ParsedTranscript(result: result, speakerNames: speakerNames)
    }

    private static func transcriptsEquivalent(_ a: String, _ b: String) -> Bool {
        normalizeTranscriptText(a) == normalizeTranscriptText(b)
    }

    private static func normalizeTranscriptText(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .newlines)
    }

    private static func transcriptText(from sidecar: TimingsSidecar) -> String {
        var lines: [String] = []
        lines.append("MecoScribe Transcript")
        lines.append("Source: \(sidecar.audioFile)")
        lines.append("Duration: \(formatTime(sidecar.durationSeconds))")
        lines.append("Speakers: \(sidecar.speakerCount)")
        lines.append(String(repeating: "-", count: 60))
        lines.append("")

        for utterance in sidecar.utterances {
            let label = sidecar.speakerNames[utterance.speakerId] ?? defaultSpeakerName(for: utterance.speakerId)
            lines.append("[\(formatTime(utterance.startTime))] \(label):")
            lines.append(utterance.text)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func defaultSpeakerName(for speakerId: String) -> String {
        if speakerId.hasPrefix("speaker_") {
            let suffix = speakerId.dropFirst("speaker_".count)
            if let number = Int(suffix) {
                return "Speaker \(number + 1)"
            }
        }
        return speakerId
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
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

struct ReconciledWords: Sendable {
    let words: [DiarizedWord]
    let consumed: Int
}

enum WordTimingReconciler {
    static func reconcileWithConsumed(
        text: String,
        speakerId: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        templateWords: [DiarizedWord]
    ) -> ReconciledWords {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else {
            return ReconciledWords(words: [], consumed: 0)
        }

        if templateWords.isEmpty {
            return ReconciledWords(
                words: distributeEvenly(
                    tokens: tokens,
                    speakerId: speakerId,
                    startTime: startTime,
                    endTime: endTime,
                    confidence: 1
                ),
                consumed: 0
            )
        }

        if tokens.count == templateWords.count {
            return ReconciledWords(
                words: zip(tokens, templateWords).map { token, template in
                    DiarizedWord(
                        word: token,
                        startTime: template.startTime,
                        endTime: template.endTime,
                        confidence: template.confidence,
                        speakerId: speakerId
                    )
                },
                consumed: templateWords.count
            )
        }

        var aligned: [DiarizedWord] = []
        var templateIndex = 0

        for tokenIndex in tokens.indices {
            let token = tokens[tokenIndex]
            var matchedIndex = -1

            if templateIndex < templateWords.count {
                for index in templateIndex..<templateWords.count {
                    if normalizeToken(token) == normalizeToken(templateWords[index].word) {
                        matchedIndex = index
                        break
                    }
                }
            }

            if matchedIndex >= 0 {
                let template = templateWords[matchedIndex]
                aligned.append(
                    DiarizedWord(
                        word: token,
                        startTime: template.startTime,
                        endTime: template.endTime,
                        confidence: template.confidence,
                        speakerId: speakerId
                    )
                )
                templateIndex = matchedIndex + 1
                continue
            }

            let nextToken = tokens[safe: tokenIndex + 1]
            let nextTemplate = templateWords[safe: templateIndex]
            let nextTokenMatchesCurrentTemplate =
                nextToken != nil &&
                nextTemplate != nil &&
                normalizeToken(nextToken!) == normalizeToken(nextTemplate!.word)

            if !nextTokenMatchesCurrentTemplate, let nextTemplate {
                aligned.append(
                    DiarizedWord(
                        word: token,
                        startTime: nextTemplate.startTime,
                        endTime: nextTemplate.endTime,
                        confidence: nextTemplate.confidence,
                        speakerId: speakerId
                    )
                )
                templateIndex += 1
                continue
            }

            let timing = timingForInsertedWord(
                previous: aligned.last,
                nextTemplate: nextTemplate,
                startTime: startTime,
                endTime: endTime
            )
            aligned.append(
                DiarizedWord(
                    word: token,
                    startTime: timing.start,
                    endTime: timing.end,
                    confidence: nextTemplate?.confidence ?? aligned.last?.confidence ?? 1,
                    speakerId: speakerId
                )
            )
        }

        return ReconciledWords(words: aligned, consumed: templateIndex)
    }

    static func reconcile(
        text: String,
        speakerId: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        templateWords: [DiarizedWord]
    ) -> [DiarizedWord] {
        reconcileWithConsumed(
            text: text,
            speakerId: speakerId,
            startTime: startTime,
            endTime: endTime,
            templateWords: templateWords
        ).words
    }

    private static func normalizeToken(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "'" }
    }

    private static func timingForInsertedWord(
        previous: DiarizedWord?,
        nextTemplate: DiarizedWord?,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> (start: TimeInterval, end: TimeInterval) {
        let gapStart = previous?.endTime ?? nextTemplate?.startTime ?? startTime
        let gapEnd = nextTemplate?.startTime ?? previous?.endTime ?? endTime
        let duration = max(gapEnd - gapStart, 0.01)
        let midpoint = gapStart + duration / 2
        let half = min(duration / 2, 0.15)
        return (
            start: max(gapStart, midpoint - half),
            end: min(gapEnd, midpoint + half)
        )
    }

    private static func distributeEvenly(
        tokens: [String],
        speakerId: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float
    ) -> [DiarizedWord] {
        let duration = max(endTime - startTime, 0.01)
        let step = duration / Double(tokens.count)

        return tokens.enumerated().map { index, token in
            let wordStart = startTime + step * Double(index)
            let wordEnd = index == tokens.count - 1 ? endTime : startTime + step * Double(index + 1)
            return DiarizedWord(
                word: token,
                startTime: wordStart,
                endTime: wordEnd,
                confidence: confidence,
                speakerId: speakerId
            )
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
