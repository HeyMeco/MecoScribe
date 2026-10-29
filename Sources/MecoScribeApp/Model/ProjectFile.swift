import Foundation
import MecoScribeCore
import UniformTypeIdentifiers

/// One transcript project: a `<base>.mscribe` container.
struct ProjectFile: Hashable, Sendable {
    let url: URL

    init(url: URL) {
        self.url = url.standardizedFileURL
    }

    init(directory: URL, baseName: String) {
        self.init(url: directory.appendingPathComponent(baseName).appendingPathExtension(MScribeFile.fileExtension))
    }

    var directory: URL { url.deletingLastPathComponent() }
    var baseName: String { url.deletingPathExtension().lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Declared as `com.heymeco.mecoscribe.project` in the app bundle; falls back to a
    /// dynamic type when running unbundled (`swift run`).
    static var contentType: UTType {
        UTType(filenameExtension: MScribeFile.fileExtension, conformingTo: .data) ?? .data
    }
}

/// The CLI's loose files for one transcript: `<base>.txt`, `<base>.mecoscribe.json`
/// and `<base>.html` in one folder. Opening them imports them into a `.mscribe`.
struct LegacyTranscriptFiles: Hashable, Sendable {
    let directory: URL
    let baseName: String

    init(directory: URL, baseName: String) {
        self.directory = directory.standardizedFileURL
        self.baseName = baseName
    }

    /// Derives the set from any of its files, or from the audio file it was made from.
    init(fileURL: URL) {
        let name = fileURL.lastPathComponent
        let sidecarSuffix = "." + TimingsSidecar.fileExtension
        if name.lowercased().hasSuffix(sidecarSuffix) {
            baseName = String(name.dropLast(sidecarSuffix.count))
        } else {
            baseName = fileURL.deletingPathExtension().lastPathComponent
        }
        directory = fileURL.deletingLastPathComponent().standardizedFileURL
    }

    var txtURL: URL { directory.appendingPathComponent(baseName + ".txt") }
    var sidecarURL: URL { directory.appendingPathComponent(baseName + "." + TimingsSidecar.fileExtension) }
    var htmlURL: URL { directory.appendingPathComponent(baseName + ".html") }
    var project: ProjectFile { ProjectFile(directory: directory, baseName: baseName) }

    var exists: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: txtURL.path)
            || fm.fileExists(atPath: sidecarURL.path)
            || fm.fileExists(atPath: htmlURL.path)
    }
}

enum ProjectLoaderError: LocalizedError {
    case noTranscript(String)

    var errorDescription: String? {
        switch self {
        case .noTranscript(let name):
            return "No MecoScribe transcript found for “\(name)”."
        }
    }
}

enum ProjectLoader {
    static let audioExtensions: Set<String> = [
        "wav", "mp3", "m4a", "aac", "flac", "aif", "aiff", "caf", "mp4", "m4v", "mov",
        "ogg", "opus", "webm", "wma", "amr", "3gp",
    ]

    static func isAudio(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if audioExtensions.contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .audiovisualContent)
    }

    static func isProject(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == MScribeFile.fileExtension
    }

    static func isLegacyTranscript(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".txt") || name.hasSuffix(".html") || name.hasSuffix(".htm")
            || name.hasSuffix("." + TimingsSidecar.fileExtension)
    }

    static func isOpenable(_ url: URL) -> Bool {
        isProject(url) || isLegacyTranscript(url) || isAudio(url)
    }

    /// Loads loose CLI files, preferring the `.txt` (merged with the timings sidecar),
    /// then the sidecar alone, then data embedded in the HTML viewer.
    static func loadLegacy(_ files: LegacyTranscriptFiles) throws -> ParsedTranscript {
        let fm = FileManager.default
        if fm.fileExists(atPath: files.txtURL.path) {
            let fallbackAudio = audioByBaseName(directory: files.directory, baseName: files.baseName)?.path ?? ""
            return try TranscriptParser.parse(txtPath: files.txtURL.path, audioPath: fallbackAudio)
        }
        if fm.fileExists(atPath: files.sidecarURL.path) {
            let sidecar = try TimingsSidecar.read(from: files.sidecarURL.path)
            return ParsedTranscript(result: sidecar.result, speakerNames: sidecar.speakerNames)
        }
        if fm.fileExists(atPath: files.htmlURL.path) {
            return try HtmlTranscriptImporter.parse(htmlPath: files.htmlURL.path)
        }
        throw ProjectLoaderError.noTranscript(files.baseName)
    }

    /// Writes `<base>.mscribe` from loose CLI files and returns it. The loose files are
    /// left untouched.
    static func importLegacy(_ files: LegacyTranscriptFiles) throws -> ProjectFile {
        let parsed = try loadLegacy(files)
        let project = files.project
        let audio = resolveAudio(
            sourceFile: parsed.result.audioFile,
            manifestAudio: nil,
            project: project
        )
        try MScribeFile.write(
            parsed.result,
            speakerNames: parsed.speakerNames,
            audioPath: audio?.path ?? absoluteSourcePath(parsed.result.audioFile, in: files.directory),
            to: project.url,
            generator: AppInfo.generator
        )
        return project
    }

    /// The best guess at an absolute path for an audio reference we could not find.
    static func absoluteSourcePath(_ sourceFile: String, in directory: URL) -> String {
        let expanded = (sourceFile as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return expanded }
        if expanded.isEmpty { return "" }
        return directory.appendingPathComponent(expanded).standardizedFileURL.path
    }

    /// Finds the audio for a project: a location the user picked, the manifest's
    /// relative then absolute path, the transcript's source path (which may be
    /// relative to a working directory we no longer know), then a same-named sibling.
    static func resolveAudio(
        sourceFile: String,
        manifestAudio: MScribeManifest.Audio?,
        project: ProjectFile
    ) -> URL? {
        let fm = FileManager.default
        let directory = project.directory
        if let override = AudioOverrides.url(for: project), fm.fileExists(atPath: override.path) {
            return override
        }
        var candidates: [URL] = []
        if let manifestAudio {
            if let relative = manifestAudio.relativePath, !relative.isEmpty {
                candidates.append(directory.appendingPathComponent(relative).standardizedFileURL)
            }
            if let absolute = manifestAudio.absolutePath, !absolute.isEmpty {
                candidates.append(URL(fileURLWithPath: absolute))
            }
            candidates.append(directory.appendingPathComponent(manifestAudio.fileName))
        }
        if !sourceFile.isEmpty {
            let expanded = (sourceFile as NSString).expandingTildeInPath
            if expanded.hasPrefix("/") {
                candidates.append(URL(fileURLWithPath: expanded))
            } else {
                candidates.append(directory.appendingPathComponent(expanded).standardizedFileURL)
            }
            candidates.append(directory.appendingPathComponent((expanded as NSString).lastPathComponent))
        }
        if let found = candidates.first(where: { !$0.hasDirectoryPath && fm.fileExists(atPath: $0.path) }) {
            return found
        }
        return audioByBaseName(directory: directory, baseName: project.baseName)
    }

    static func audioByBaseName(directory: URL, baseName: String) -> URL? {
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        else { return nil }
        return contents
            .filter { $0.deletingPathExtension().lastPathComponent == baseName && isAudio($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }
}

/// Audio files the user located manually, remembered per project.
enum AudioOverrides {
    private static let key = "audioOverrides"

    static func url(for project: ProjectFile) -> URL? {
        let map = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        return map[project.url.path].map { URL(fileURLWithPath: $0) }
    }

    static func set(_ url: URL, for project: ProjectFile) {
        var map = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        map[project.url.path] = url.path
        UserDefaults.standard.set(map, forKey: key)
    }
}

enum AppInfo {
    static var version: String { MecoScribeVersion.current }

    static var generator: String { "MecoScribe \(version)" }
}
