import FluidAudio
import Foundation

enum ModelCache {
    private static let defaultFolderName = "models"

    static func resolveDirectory(customPath: String?) throws -> URL {
        let url: URL
        if let customPath, !customPath.isEmpty {
            url = URL(fileURLWithPath: customPath, isDirectory: true)
        } else if let env = ProcessInfo.processInfo.environment["MECOSCRIBE_MODELS_DIR"],
            !env.isEmpty
        {
            url = URL(fileURLWithPath: env, isDirectory: true)
        } else {
            url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent(defaultFolderName, isDirectory: true)
        }

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    static func diarizerDirectory(base: URL) -> URL {
        base.appendingPathComponent(Repo.diarizer.folderName, isDirectory: true)
    }

    static func asrDirectory(base: URL, version: AsrModelVersion) -> URL {
        base.appendingPathComponent(asrRepo(for: version).folderName, isDirectory: true)
    }

    private static func asrRepo(for version: AsrModelVersion) -> Repo {
        switch version {
        case .v2:
            return .parakeetV2
        case .v3:
            return .parakeetV3
        case .tdtCtc110m:
            return .parakeetTdtCtc110m
        case .tdtJa:
            return .parakeetJa
        }
    }
}
