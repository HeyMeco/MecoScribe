import Foundation

/// Reads the transcript data embedded in an HTML viewer produced by `HtmlExporter`.
public enum HtmlTranscriptImporter {
    public static func parse(htmlPath: String) throws -> ParsedTranscript {
        try parse(html: String(contentsOfFile: htmlPath, encoding: .utf8))
    }

    public static func parse(html: String) throws -> ParsedTranscript {

        guard
            let utterancesJSON = value(in: html, prefix: "let utterances = ", suffix: ";"),
            let utterances = try? JSONDecoder().decode(
                [DiarizedUtterance].self,
                from: Data(utterancesJSON.utf8)
            )
        else {
            throw HtmlTranscriptImporterError.noTranscriptData
        }

        var speakerIds: [String] = []
        if let json = value(in: html, prefix: "let speakerIds = ", suffix: ";"),
            let decoded = try? JSONDecoder().decode([String].self, from: Data(json.utf8))
        {
            speakerIds = decoded
        }
        for utterance in utterances where !speakerIds.contains(utterance.speakerId) {
            speakerIds.append(utterance.speakerId)
        }

        var speakerNames: [String: String] = [:]
        if let json = value(in: html, prefix: "let speakerNames = Object.assign({}, ", suffix: ");"),
            let decoded = try? JSONDecoder().decode([String: String].self, from: Data(json.utf8))
        {
            speakerNames = decoded
        }

        let sourceFile = value(in: html, prefix: "const sourceFile = \"", suffix: "\";")
            .map(unescapeHTML) ?? ""
        let duration = value(in: html, prefix: "const durationSeconds = ", suffix: ";")
            .flatMap(TimeInterval.init) ?? (utterances.last?.endTime ?? 0)

        let result = ScribeResult(
            audioFile: sourceFile,
            durationSeconds: duration,
            speakerCount: speakerIds.count,
            utterances: utterances,
            speakerIds: speakerIds
        )
        return ParsedTranscript(result: result, speakerNames: speakerNames)
    }

    /// Returns the rest of the first line that starts with `prefix` (after trimming),
    /// with `suffix` removed from its end.
    private static func value(in html: String, prefix: String, suffix: String) -> String? {
        for rawLine in html.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(prefix), line.hasSuffix(suffix) else { continue }
            let body = line.dropFirst(prefix.count).dropLast(suffix.count)
            return String(body)
        }
        return nil
    }

    private static func unescapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

public enum HtmlTranscriptImporterError: LocalizedError {
    case noTranscriptData

    public var errorDescription: String? {
        switch self {
        case .noTranscriptData:
            return "This HTML file does not contain MecoScribe transcript data"
        }
    }
}
