import Foundation
import Testing

@testable import MecoScribeApp

@MainActor
struct UpdateCheckerTests {
    private func defaults() -> UserDefaults {
        let suite = "mecoscribe-update-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: Preferences.checkForUpdatesAutomatically)
        return defaults
    }

    nonisolated private static func payload(tag: String, assets: String = "[]") -> Data {
        Data("""
        {"tag_name": "\(tag)", "name": "Version \(tag)", "body": "Notes for \(tag)",
         "html_url": "https://github.com/HeyMeco/MecoScribe/releases/tag/\(tag)",
         "assets": \(assets)}
        """.utf8)
    }

    @Test func comparesVersions() {
        #expect(UpdateChecker.isNewer("2.0.1", than: "2.0.0"))
        #expect(UpdateChecker.isNewer("v2.1", than: "2.0.9"))
        #expect(UpdateChecker.isNewer("10.0.0", than: "9.9.9"))
        #expect(!UpdateChecker.isNewer("2.0", than: "2.0.0"))
        #expect(!UpdateChecker.isNewer("1.0.1", than: "2.0.0"))
        #expect(!UpdateChecker.isNewer("2.0.0-beta", than: "2.0.0"))
        #expect(!UpdateChecker.isNewer("nightly", than: "2.0.0"))
    }

    @Test func parsesReleaseAndPrefersDiskImage() throws {
        let assets = """
        [{"name": "MecoScribe.zip", "browser_download_url": "https://example.com/MecoScribe.zip"},
         {"name": "MecoScribe.dmg", "browser_download_url": "https://example.com/MecoScribe.dmg"}]
        """
        let release = try UpdateChecker.parseRelease(Self.payload(tag: "v2.1.0", assets: assets))
        #expect(release.version == "2.1.0")
        #expect(release.name == "Version v2.1.0")
        #expect(release.downloadURL?.lastPathComponent == "MecoScribe.dmg")
        #expect(release.pageURL.absoluteString.hasSuffix("/tag/v2.1.0"))
    }

    @Test func reportsAvailableAndUpToDate() async {
        let newer = UpdateChecker(currentVersion: "2.0.0", defaults: defaults()) { Self.payload(tag: "2.1.0") }
        let state = await newer.check()
        #expect(state == newer.state)
        #expect(newer.availableRelease?.version == "2.1.0")
        #expect(newer.availableRelease?.downloadURL == nil)

        let same = UpdateChecker(currentVersion: "2.0.0", defaults: defaults()) { Self.payload(tag: "2.0.0") }
        #expect(await same.check() == .upToDate)
    }

    @Test func reportsFailures() async {
        let checker = UpdateChecker(currentVersion: "2.0.0", defaults: defaults()) {
            throw UpdateChecker.UpdateError.badResponse(500)
        }
        guard case .failed(let message) = await checker.check() else {
            Issue.record("expected a failure")
            return
        }
        #expect(message.contains("500"))
        #expect(checker.lastCheckedAt == nil)
    }

    @Test func schedulesDailyChecksAndRemembersSkips() async {
        let store = defaults()
        let checker = UpdateChecker(currentVersion: "2.0.0", defaults: store) { Self.payload(tag: "2.1.0") }
        #expect(checker.shouldCheckAutomatically())
        await checker.check()
        #expect(!checker.shouldCheckAutomatically())
        #expect(checker.shouldCheckAutomatically(now: Date().addingTimeInterval(25 * 60 * 60)))

        let release = try! #require(checker.availableRelease)
        #expect(!checker.isSkipped(release))
        checker.skip(release)
        #expect(checker.isSkipped(release))

        store.set(false, forKey: Preferences.checkForUpdatesAutomatically)
        #expect(!checker.shouldCheckAutomatically(now: Date().addingTimeInterval(48 * 60 * 60)))
    }
}
