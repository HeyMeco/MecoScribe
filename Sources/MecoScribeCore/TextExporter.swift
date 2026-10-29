import Foundation

public enum TextExporter {
    public static func export(_ result: ScribeResult, speakerNames: [String: String], to path: String) throws {
        try text(for: result, speakerNames: speakerNames)
            .write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// The plain-text transcript format shared by the CLI, the HTML viewer, and the app.
    public static func text(for result: ScribeResult, speakerNames: [String: String]) -> String {
        var lines: [String] = []
        lines.append("MecoScribe Transcript")
        lines.append("Source: \(result.audioFile)")
        lines.append("Duration: \(formatTime(result.durationSeconds))")
        lines.append("Speakers: \(result.speakerCount)")
        lines.append(String(repeating: "-", count: 60))
        lines.append("")

        for utterance in result.utterances {
            let label = speakerNames[utterance.speakerId] ?? displayName(for: utterance.speakerId)
            lines.append("[\(formatTime(utterance.startTime))] \(label):")
            lines.append(utterance.text)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    public static func displayName(for speakerId: String) -> String {
        if speakerId.hasPrefix("speaker_") {
            let suffix = speakerId.dropFirst("speaker_".count)
            if let number = Int(suffix) {
                return "Speaker \(number + 1)"
            }
        }
        return speakerId
    }

    public static func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
