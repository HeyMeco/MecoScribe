import SwiftUI

struct SettingsView: View {
    @AppStorage(Preferences.modelsDirectory) private var modelsDirectory = ""
    @AppStorage(Preferences.followPlayback) private var followPlayback = false
    @AppStorage(Preferences.transcriptFontSize) private var fontSize = 15.0
    @AppStorage(Preferences.checkForUpdatesAutomatically) private var checkForUpdates = true
    private var updates: UpdateChecker { UpdateChecker.shared }

    var body: some View {
        Form {
            Section("Saving") {
                Text("Edits save automatically to the project's .mscribe file, which holds the transcript (.txt), word timings (.mecoscribe.json) and the HTML viewer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Editor") {
                Toggle("Follow playback", isOn: $followPlayback)
                LabeledContent("Text size") {
                    Stepper(value: $fontSize, in: 11...28, step: 1) {
                        Text("\(Int(fontSize)) pt").monospacedDigit()
                    }
                }
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $checkForUpdates)
                LabeledContent("MecoScribe \(updates.currentVersion)") {
                    HStack {
                        updateStatus
                        Button("Check Now") {
                            Task { await UpdatePrompt.checkInteractively() }
                        }
                        .disabled(updates.state == .checking)
                    }
                }
            }
            Section("Models") {
                LabeledContent("Model cache") {
                    VStack(alignment: .trailing) {
                        Text(Preferences.modelsDirectoryURL.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.head)
                        HStack {
                            if !modelsDirectory.isEmpty {
                                Button("Use Default") { modelsDirectory = "" }
                            }
                            Button("Choose…") {
                                if let url = FilePanels.chooseDirectory(
                                    title: "Model Cache Folder",
                                    startingAt: Preferences.modelsDirectoryURL
                                ) {
                                    modelsDirectory = url.path
                                }
                            }
                            Button("Show in Finder") {
                                let url = Preferences.modelsDirectoryURL
                                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updates.state {
        case .checking:
            ProgressView().controlSize(.small)
        case .available(let release):
            Button("Version \(release.version) available") { UpdatePrompt.open(release) }
                .buttonStyle(.link)
        case .upToDate:
            Text("Up to date").foregroundStyle(.secondary)
        case .failed:
            Text("Check failed").foregroundStyle(.secondary)
        case .idle:
            if let last = updates.lastCheckedAt {
                Text("Checked \(last.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary)
            }
        }
    }
}
