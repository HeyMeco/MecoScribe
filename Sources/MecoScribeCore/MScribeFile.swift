import Foundation

/// `manifest.json` at the root of a `.mscribe` container.
public struct MScribeManifest: Codable, Sendable, Equatable {
    public static let formatIdentifier = "mecoscribe"
    public static let currentSchemaVersion = "1.0"

    public struct Audio: Codable, Sendable, Equatable {
        /// File name of the audio, e.g. `meeting.m4a`.
        public var fileName: String
        /// Path relative to the folder containing the `.mscribe` file, when one exists.
        public var relativePath: String?
        /// Absolute path at the time the container was written.
        public var absolutePath: String?

        public init(fileName: String, relativePath: String?, absolutePath: String?) {
            self.fileName = fileName
            self.relativePath = relativePath
            self.absolutePath = absolutePath
        }
    }

    public struct Contents: Codable, Sendable, Equatable {
        public var transcript: String
        public var timings: String
        public var viewer: String

        public init(transcript: String, timings: String, viewer: String) {
            self.transcript = transcript
            self.timings = timings
            self.viewer = viewer
        }
    }

    public var format: String
    public var schemaVersion: String
    public var generator: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var audio: Audio
    public var contents: Contents

    public init(
        generator: String,
        createdAt: Date,
        modifiedAt: Date,
        audio: Audio,
        contents: Contents = MScribeFile.defaultContents
    ) {
        format = Self.formatIdentifier
        schemaVersion = Self.currentSchemaVersion
        self.generator = generator
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.audio = audio
        self.contents = contents
    }
}

/// A transcript read from a `.mscribe` container.
public struct MScribeDocument: Sendable {
    public var manifest: MScribeManifest
    public var transcript: ParsedTranscript
    /// The transcript text as stored in the container.
    public var transcriptText: String
}

public enum MScribeError: LocalizedError {
    case notMScribe
    case unsupportedSchema(String)
    case missingTranscript

    public var errorDescription: String? {
        switch self {
        case .notMScribe:
            return "The file is not a MecoScribe project."
        case .unsupportedSchema(let version):
            return "The project uses schema version \(version), which this version of MecoScribe cannot read. Please update MecoScribe."
        case .missingTranscript:
            return "The project does not contain a transcript."
        }
    }
}

/// A `.mscribe` file is a ZIP container holding the transcript (`transcript.txt`), its
/// word timings (`transcript.mecoscribe.json`), the standalone HTML viewer
/// (`transcript.html`) and a `manifest.json` describing schema version 1.0. Unzipped
/// next to the audio, the files work exactly like the CLI's output.
public enum MScribeFile {
    public static let fileExtension = "mscribe"
    public static let manifestName = "manifest.json"
    public static let defaultContents = MScribeManifest.Contents(
        transcript: "transcript.txt",
        timings: "transcript." + TimingsSidecar.fileExtension,
        viewer: "transcript.html"
    )

    /// Writes a container for `result`. `audioPath` is the audio file it belongs to;
    /// `createdAt` should be carried over when re-saving an existing project.
    public static func write(
        _ result: ScribeResult,
        speakerNames: [String: String],
        audioPath: String,
        to url: URL,
        generator: String = "MecoScribe",
        createdAt: Date? = nil
    ) throws {
        let directory = url.deletingLastPathComponent().standardizedFileURL
        let contents = defaultContents
        let now = Date()

        let audioURL = URL(fileURLWithPath: audioPath).standardizedFileURL
        let manifest = MScribeManifest(
            generator: generator,
            createdAt: createdAt ?? now,
            modifiedAt: now,
            audio: .init(
                fileName: audioURL.lastPathComponent,
                relativePath: audioPath.isEmpty ? nil : relativePath(from: directory, to: audioURL),
                absolutePath: audioPath.isEmpty ? nil : audioURL.path
            ),
            contents: contents
        )

        let text = TextExporter.text(for: result, speakerNames: speakerNames)
        let timingsEncoder = JSONEncoder()
        timingsEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let timings = try timingsEncoder.encode(TimingsSidecar(result: result, speakerNames: speakerNames))
        // Rendered as if it sat beside the container, so unzipping in place keeps the
        // audio link working.
        let html = try HtmlExporter.render(
            result,
            audioPath: audioURL.path,
            htmlPath: directory.appendingPathComponent(contents.viewer).path,
            speakerNames: speakerNames
        )

        let manifestEncoder = JSONEncoder()
        manifestEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        manifestEncoder.dateEncodingStrategy = .iso8601
        let manifestData = try manifestEncoder.encode(manifest)

        try ZipArchive.write(
            [
                .init(name: manifestName, data: manifestData, modified: now),
                .init(name: contents.transcript, data: Data(text.utf8), modified: now),
                .init(name: contents.timings, data: timings, modified: now),
                .init(name: contents.viewer, data: Data(html.utf8), modified: now),
            ],
            to: url
        )
    }

    public static func read(from url: URL) throws -> MScribeDocument {
        let entries: [String: Data]
        do {
            entries = try ZipArchive.read(contentsOf: url)
        } catch ZipArchive.ZipError.notAZipFile {
            throw MScribeError.notMScribe
        }
        return try read(entries: entries)
    }

    public static func read(entries rawEntries: [String: Data]) throws -> MScribeDocument {
        // Finder's "Compress" puts everything inside a top-level folder; accept that too.
        var entries = rawEntries
        if entries[manifestName] == nil,
            let nested = entries.keys.first(where: { $0.hasSuffix("/" + manifestName) })
        {
            let prefix = String(nested.dropLast(manifestName.count))
            entries = Dictionary(
                uniqueKeysWithValues: rawEntries.compactMap { key, value in
                    key.hasPrefix(prefix) ? (String(key.dropFirst(prefix.count)), value) : nil
                }
            )
        }

        guard let manifestData = entries[manifestName] else { throw MScribeError.notMScribe }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(MScribeManifest.self, from: manifestData),
            manifest.format == MScribeManifest.formatIdentifier
        else {
            throw MScribeError.notMScribe
        }
        let major = manifest.schemaVersion.split(separator: ".").first.flatMap { Int($0) }
        guard major == 1 else { throw MScribeError.unsupportedSchema(manifest.schemaVersion) }

        let contents = manifest.contents
        let text = entries[contents.transcript].map { String(decoding: $0, as: UTF8.self) }
        let timings = entries[contents.timings].flatMap { try? JSONDecoder().decode(TimingsSidecar.self, from: $0) }
        let audioPath = manifest.audio.absolutePath ?? manifest.audio.fileName

        let transcript: ParsedTranscript
        if let text {
            // The text wins: it may have been edited by hand after unzipping. The
            // parser reconciles it with the timings, which it finds beside the `.txt`.
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("mscribe-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let txtURL = scratch.appendingPathComponent("transcript.txt")
            try Data(text.utf8).write(to: txtURL)
            if let data = entries[contents.timings] {
                try data.write(to: URL(fileURLWithPath: TimingsSidecar.path(forTxtPath: txtURL.path)))
            }
            transcript = try TranscriptParser.parse(txtPath: txtURL.path, audioPath: audioPath)
        } else if let timings {
            transcript = ParsedTranscript(result: timings.result, speakerNames: timings.speakerNames)
        } else if let html = entries[contents.viewer] {
            transcript = try HtmlTranscriptImporter.parse(html: String(decoding: html, as: UTF8.self))
        } else {
            throw MScribeError.missingTranscript
        }

        return MScribeDocument(
            manifest: manifest,
            transcript: transcript,
            transcriptText: text ?? TextExporter.text(for: transcript.result, speakerNames: transcript.speakerNames)
        )
    }

    /// `/a/b` → `/a/c/x.wav` gives `../c/x.wav`.
    static func relativePath(from directory: URL, to target: URL) -> String {
        let base = directory.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let path = target.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        var common = 0
        while common < base.count, common < path.count, base[common] == path[common] {
            common += 1
        }
        let ups = Array(repeating: "..", count: base.count - common)
        return (ups + path[common...]).joined(separator: "/")
    }
}
