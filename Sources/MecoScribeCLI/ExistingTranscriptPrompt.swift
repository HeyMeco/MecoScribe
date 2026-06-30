import Darwin
import Foundation

enum ExistingTranscriptChoice {
    case htmlOnly
    case both
}

enum ExistingTranscriptPrompt {
    static func resolve(
        txtPath: String,
        htmlOnlyFlag: Bool,
        bothFlag: Bool
    ) -> ExistingTranscriptChoice? {
        guard FileManager.default.fileExists(atPath: txtPath) else {
            return .both
        }

        if htmlOnlyFlag { return .htmlOnly }
        if bothFlag { return .both }

        guard isatty(STDIN_FILENO) != 0 else {
            fputs(
                "Found existing transcript at \(txtPath). Use --html-only or --both.\n",
                stderr
            )
            return nil
        }

        let fileName = URL(fileURLWithPath: txtPath).lastPathComponent
        print("")
        print("Found existing transcript: \(fileName)")
        print("  1) HTML only  — keep the .txt, regenerate the HTML viewer")
        print("  2) Both       — re-transcribe and overwrite .txt and .html")
        print("")
        print("Choice [1/2] (default: 1): ", terminator: "")

        let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        if line.isEmpty || line == "1" || line == "html" || line == "html-only" {
            return .htmlOnly
        }
        if line == "2" || line == "both" {
            return .both
        }

        print("Unknown choice, using HTML only.")
        return .htmlOnly
    }
}
