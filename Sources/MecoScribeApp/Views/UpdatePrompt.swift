import AppKit

/// Presents update-check results.
@MainActor
enum UpdatePrompt {
    /// "Check for Updates…": always reports the outcome.
    static func checkInteractively() async {
        let checker = UpdateChecker.shared
        switch await checker.check() {
        case .available(let release):
            present(release, allowSkip: false)
        case .upToDate:
            let alert = NSAlert()
            alert.messageText = "You’re up to date"
            alert.informativeText = "MecoScribe \(checker.currentVersion) is the latest version."
            alert.runModal()
        case .failed(let message):
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t check for updates"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open Releases Page")
            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.open(UpdateChecker.releasesPageURL)
            }
        case .idle, .checking:
            break
        }
    }

    /// Launch-time check: silent unless a version the user has not skipped is out.
    static func checkAutomaticallyIfDue() async {
        let checker = UpdateChecker.shared
        guard checker.shouldCheckAutomatically() else { return }
        if case .available(let release) = await checker.check(), !checker.isSkipped(release) {
            present(release, allowSkip: true)
        }
    }

    static func present(_ release: AppRelease, allowSkip: Bool) {
        let alert = NSAlert()
        alert.messageText = "MecoScribe \(release.version) is available"
        var info = "You have version \(UpdateChecker.shared.currentVersion)."
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            info += "\n\n" + (notes.count > 700 ? String(notes.prefix(700)) + "…" : notes)
        }
        alert.informativeText = info
        alert.addButton(withTitle: release.downloadURL == nil ? "View Release" : "Download")
        alert.addButton(withTitle: "Later")
        if allowSkip { alert.addButton(withTitle: "Skip This Version") }
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            open(release)
        case .alertThirdButtonReturn:
            UpdateChecker.shared.skip(release)
        default:
            break
        }
    }

    static func open(_ release: AppRelease) {
        NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
    }
}
