import Foundation

public enum HtmlExporter {
    public static func export(
        _ result: ScribeResult,
        audioPath: String,
        htmlPath: String,
        speakerNames: [String: String]
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let utterancesJSON = String(data: try encoder.encode(result.utterances), encoding: .utf8) ?? "[]"
        let speakerIdsJSON = String(data: try encoder.encode(result.speakerIds), encoding: .utf8) ?? "[]"
        let speakerNamesJSON = String(data: try encoder.encode(speakerNames), encoding: .utf8) ?? "{}"

        let audioFileName = URL(fileURLWithPath: audioPath).lastPathComponent
        let htmlDirectory = URL(fileURLWithPath: htmlPath).deletingLastPathComponent().path
        let audioSourcePath = relativePath(from: htmlDirectory, to: URL(fileURLWithPath: audioPath).path)

        let txtBaseName = URL(fileURLWithPath: htmlPath).deletingPathExtension().lastPathComponent + ".txt"
        let timingsBaseName = URL(fileURLWithPath: htmlPath).deletingPathExtension().lastPathComponent + ".mecoscribe.json"

        let html = try renderTemplate(
            title: audioFileName,
            txtBaseName: txtBaseName,
            timingsBaseName: timingsBaseName,
            audioSrc: audioSourcePath,
            sourceFile: result.audioFile,
            duration: formatDuration(result.durationSeconds),
            durationSeconds: result.durationSeconds,
            speakerCount: result.speakerCount,
            utterancesJSON: utterancesJSON,
            speakerIdsJSON: speakerIdsJSON,
            speakerNamesJSON: speakerNamesJSON
        )

        try html.write(toFile: htmlPath, atomically: true, encoding: .utf8)
    }

    public static func renderTemplate(
        title: String,
        txtBaseName: String,
        timingsBaseName: String,
        audioSrc: String,
        sourceFile: String,
        duration: String,
        durationSeconds: TimeInterval,
        speakerCount: Int,
        utterancesJSON: String,
        speakerIdsJSON: String,
        speakerNamesJSON: String
    ) throws -> String {
        let template = try loadTemplate()
        return template
            .replacingOccurrences(of: "{{TITLE}}", with: escapeHTML(title))
            .replacingOccurrences(of: "{{TXT_BASENAME}}", with: escapeHTML(txtBaseName))
            .replacingOccurrences(of: "{{TIMINGS_BASENAME}}", with: escapeHTML(timingsBaseName))
            .replacingOccurrences(of: "{{AUDIO_SRC}}", with: escapeHTML(audioSrc))
            .replacingOccurrences(of: "{{SOURCE_FILE}}", with: escapeHTML(sourceFile))
            .replacingOccurrences(of: "{{DURATION}}", with: escapeHTML(duration))
            .replacingOccurrences(of: "{{DURATION_SECONDS}}", with: "\(durationSeconds)")
            .replacingOccurrences(of: "{{SPEAKER_COUNT}}", with: "\(speakerCount)")
            .replacingOccurrences(of: "{{UTTERANCES_JSON}}", with: utterancesJSON)
            .replacingOccurrences(of: "{{SPEAKER_IDS_JSON}}", with: speakerIdsJSON)
            .replacingOccurrences(of: "{{SPEAKER_NAMES_JSON}}", with: speakerNamesJSON)
    }

    public static func loadTemplate() throws -> String {
        guard let url = Bundle.module.url(forResource: "editor-template", withExtension: "html") else {
            throw HtmlExporterError.templateNotFound
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func relativePath(from directory: String, to target: String) -> String {
        let dirURL = URL(fileURLWithPath: directory).standardizedFileURL
        let targetURL = URL(fileURLWithPath: target).standardizedFileURL
        return targetURL.path.replacingOccurrences(of: dirURL.path + "/", with: "")
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

public enum HtmlExporterError: Error, LocalizedError {
    case templateNotFound

    public var errorDescription: String? {
        switch self {
        case .templateNotFound:
            return "Editor HTML template not found in bundle"
        }
    }
}
