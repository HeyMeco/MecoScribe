import Foundation

public struct ParsedTranscript {
    public let result: ScribeResult
    public let speakerNames: [String: String]
}

public enum TranscriptParser {
    public static func parse(txtPath: String, audioPath: String) throws -> ParsedTranscript {
        let sidecarPath = TimingsSidecar.path(forTxtPath: txtPath)
        if FileManager.default.fileExists(atPath: sidecarPath),
            let sidecar = try? TimingsSidecar.read(from: sidecarPath)
        {
            return try TimingsSidecar.merge(txtPath: txtPath, sidecar: sidecar, audioPath: audioPath)
        }

        let text = try String(contentsOfFile: txtPath, encoding: .utf8)
        let lines = text.components(separatedBy: .newlines)

        var sourceFile = audioPath
        var durationSeconds: TimeInterval = 0
        var speakerCount = 0

        for line in lines.prefix(10) {
            if line.hasPrefix("Source: ") {
                sourceFile = String(line.dropFirst("Source: ".count))
            } else if line.hasPrefix("Duration: ") {
                durationSeconds = parseDuration(String(line.dropFirst("Duration: ".count))) ?? 0
            } else if line.hasPrefix("Speakers: "), let count = Int(line.dropFirst("Speakers: ".count)) {
                speakerCount = count
            }
        }

        let segments = parseSegments(from: lines)
        guard !segments.isEmpty else {
            throw TranscriptParserError.noSegments
        }

        var speakerIds: [String] = []
        var speakerNames: [String: String] = [:]
        var utterances: [DiarizedUtterance] = []

        for (index, segment) in segments.enumerated() {
            let speakerId = resolveSpeakerId(
                label: segment.speakerLabel,
                speakerIds: &speakerIds,
                speakerNames: &speakerNames
            )

            let startTime = segment.startTime
            let endTime: TimeInterval
            if index + 1 < segments.count {
                endTime = segments[index + 1].startTime
            } else {
                endTime = max(startTime + 1, durationSeconds)
            }

            let words = WordTimingReconciler.reconcile(
                text: segment.text,
                speakerId: speakerId,
                startTime: startTime,
                endTime: endTime,
                templateWords: []
            )
            utterances.append(
                DiarizedUtterance(
                    speakerId: speakerId,
                    startTime: startTime,
                    endTime: endTime,
                    text: segment.text,
                    words: words
                ))
        }

        if durationSeconds <= 0, let last = utterances.last {
            durationSeconds = last.endTime
        }
        if speakerCount == 0 {
            speakerCount = speakerIds.count
        }

        let result = ScribeResult(
            audioFile: sourceFile,
            durationSeconds: durationSeconds,
            speakerCount: speakerCount,
            utterances: utterances,
            speakerIds: speakerIds
        )
        return ParsedTranscript(result: result, speakerNames: speakerNames)
    }

    static func parseSegmentsPublic(from lines: [String]) -> [TranscriptSegment] {
        parseSegments(from: lines).map {
            TranscriptSegment(startTime: $0.startTime, speakerLabel: $0.speakerLabel, text: $0.text)
        }
    }

    static func resolveSpeakerIdPublic(
        label: String,
        speakerIds: inout [String],
        speakerNames: inout [String: String]
    ) -> String {
        resolveSpeakerId(label: label, speakerIds: &speakerIds, speakerNames: &speakerNames)
    }

    struct TranscriptSegment {
        let startTime: TimeInterval
        let speakerLabel: String
        let text: String
    }

    private struct Segment {
        let startTime: TimeInterval
        let speakerLabel: String
        let text: String
    }

    private static func parseSegments(from lines: [String]) -> [Segment] {
        var index = 0
        while index < lines.count {
            if lines[index].filter({ $0 == "-" }).count >= 20 {
                index += 1
                break
            }
            index += 1
        }

        var segments: [Segment] = []
        while index < lines.count {
            while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
            }
            guard index < lines.count else { break }

            guard let header = parseHeaderLine(lines[index]) else {
                index += 1
                continue
            }
            index += 1

            var bodyLines: [String] = []
            while index < lines.count {
                let line = lines[index]
                if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
                if parseHeaderLine(line) != nil { break }
                bodyLines.append(line)
                index += 1
            }

            let body = bodyLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !body.isEmpty {
                segments.append(Segment(startTime: header.startTime, speakerLabel: header.speakerLabel, text: body))
            }
        }

        return segments
    }

    private static func parseHeaderLine(_ line: String) -> (startTime: TimeInterval, speakerLabel: String)? {
        let pattern = #"^\[((?:\d+:)?\d{2}:\d{2})\]\s*(.+):\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
            let timeRange = Range(match.range(at: 1), in: line),
            let labelRange = Range(match.range(at: 2), in: line),
            let startTime = parseTimestamp(String(line[timeRange]))
        else { return nil }

        return (startTime, String(line[labelRange]))
    }

    private static func parseTimestamp(_ value: String) -> TimeInterval? {
        let parts = value.split(separator: ":").map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }

        if parts.count == 2 {
            guard let minutes = Int(parts[0]), let seconds = Int(parts[1]) else { return nil }
            return TimeInterval(minutes * 60 + seconds)
        }

        guard let hours = Int(parts[0]), let minutes = Int(parts[1]), let seconds = Int(parts[2]) else {
            return nil
        }
        return TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

    private static func parseDuration(_ value: String) -> TimeInterval? {
        parseTimestamp(value.trimmingCharacters(in: .whitespaces))
    }

    private static func resolveSpeakerId(
        label: String,
        speakerIds: inout [String],
        speakerNames: inout [String: String]
    ) -> String {
        if let existing = speakerNames.first(where: { $0.value == label })?.key {
            return existing
        }

        for id in speakerIds where defaultSpeakerName(for: id) == label {
            return id
        }

        let id = "speaker_\(speakerIds.count)"
        speakerIds.append(id)
        if label != defaultSpeakerName(for: id) {
            speakerNames[id] = label
        }
        return id
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
}

enum TranscriptParserError: LocalizedError {
    case noSegments

    var errorDescription: String? {
        switch self {
        case .noSegments:
            return "Could not parse any transcript segments from the .txt file"
        }
    }
}
