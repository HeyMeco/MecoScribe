import Foundation
import MecoScribeCore
import Observation

/// A published GitHub release.
struct AppRelease: Equatable, Sendable {
    var version: String
    var name: String
    var notes: String
    var pageURL: URL
    /// A downloadable build attached to the release (`.dmg` or `.zip`), if any.
    var downloadURL: URL?
}

/// Dotted numeric versions (`2.0.0`, `v2.1`, `2.1.0-beta`): compares the numbers and
/// ignores any suffix after `-` or `+`.
struct SemanticVersion: Comparable, Sendable {
    let components: [Int]

    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        if let cut = text.firstIndex(where: { $0 == "-" || $0 == "+" }) { text = String(text[..<cut]) }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        components = parts.compactMap { $0 }
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// Checks GitHub Releases for a newer MecoScribe. It only notifies; downloading opens
/// the release in the browser.
@MainActor
@Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case failed(String)
    }

    enum UpdateError: LocalizedError {
        case badResponse(Int)
        case noReleases

        var errorDescription: String? {
            switch self {
            case .badResponse(let status): return "GitHub returned an error (HTTP \(status))."
            case .noReleases: return "No releases have been published yet."
            }
        }
    }

    static let shared = UpdateChecker()
    nonisolated static let latestReleaseURL = URL(string: "https://api.github.com/repos/HeyMeco/MecoScribe/releases/latest")!
    nonisolated static let releasesPageURL = URL(string: "https://github.com/HeyMeco/MecoScribe/releases")!
    static let automaticInterval: TimeInterval = 24 * 60 * 60

    private(set) var state: State = .idle
    let currentVersion: String

    /// Returns the release JSON. Replaceable for tests.
    @ObservationIgnored private let fetch: @Sendable () async throws -> Data
    @ObservationIgnored private let defaults: UserDefaults

    init(
        currentVersion: String = MecoScribeVersion.current,
        defaults: UserDefaults = .standard,
        fetch: (@Sendable () async throws -> Data)? = nil
    ) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.fetch = fetch ?? Self.fetchFromGitHub
    }

    var availableRelease: AppRelease? {
        if case .available(let release) = state { return release }
        return nil
    }

    var lastCheckedAt: Date? {
        defaults.object(forKey: Preferences.lastUpdateCheck) as? Date
    }

    /// Whether a launch-time check is due: enabled, and the last one is a day old.
    func shouldCheckAutomatically(now: Date = Date()) -> Bool {
        guard defaults.bool(forKey: Preferences.checkForUpdatesAutomatically) else { return false }
        guard let last = lastCheckedAt else { return true }
        return now.timeIntervalSince(last) >= Self.automaticInterval
    }

    func isSkipped(_ release: AppRelease) -> Bool {
        defaults.string(forKey: Preferences.skippedUpdateVersion) == release.version
    }

    func skip(_ release: AppRelease) {
        defaults.set(release.version, forKey: Preferences.skippedUpdateVersion)
    }

    /// Fetches the latest release and updates `state`.
    @discardableResult
    func check() async -> State {
        guard state != .checking else { return state }
        state = .checking
        do {
            let data = try await fetch()
            let release = try Self.parseRelease(data)
            defaults.set(Date(), forKey: Preferences.lastUpdateCheck)
            state = Self.isNewer(release.version, than: currentVersion) ? .available(release) : .upToDate
        } catch {
            state = .failed(error.localizedDescription)
        }
        return state
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let candidate = SemanticVersion(candidate), let current = SemanticVersion(current) else {
            return false
        }
        return candidate > current
    }

    private struct ReleasePayload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: URL
        let assets: [Asset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlURL = "html_url"
            case assets
        }
    }

    static func parseRelease(_ data: Data) throws -> AppRelease {
        let payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
        var version = payload.tagName.trimmingCharacters(in: .whitespaces)
        if version.first == "v" || version.first == "V" { version.removeFirst() }
        let assets = payload.assets ?? []
        let download = assets.first { $0.name.lowercased().hasSuffix(".dmg") }
            ?? assets.first { $0.name.lowercased().hasSuffix(".zip") }
        return AppRelease(
            version: version,
            name: payload.name?.isEmpty == false ? payload.name! : "MecoScribe \(version)",
            notes: payload.body ?? "",
            pageURL: payload.htmlURL,
            downloadURL: download?.browserDownloadURL
        )
    }

    private static let fetchFromGitHub: @Sendable () async throws -> Data = {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MecoScribe/\(MecoScribeVersion.current)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw UpdateError.noReleases }
        guard (200..<300).contains(status) else { throw UpdateError.badResponse(status) }
        return data
    }
}
