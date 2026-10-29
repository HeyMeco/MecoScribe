import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    let workspace: Workspace
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.tint)
                VStack(spacing: 6) {
                    Text("MecoScribe")
                        .font(.largeTitle.weight(.semibold))
                    Text("Diarized transcription on your Mac")
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 10) {
                    Button {
                        workspace.startSetup(audio: nil)
                    } label: {
                        Label("New Transcription…", systemImage: "plus.circle")
                            .frame(width: 220)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)

                    Button {
                        if let url = FilePanels.openTranscriptOrAudio() {
                            workspace.open(url)
                        }
                    } label: {
                        Label("Open Project…", systemImage: "doc.text")
                            .frame(width: 220)
                    }
                    .controlSize(.large)
                }
                Text("Or drop an audio file or .mscribe project here")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if let release = UpdateChecker.shared.availableRelease {
                    Button {
                        UpdatePrompt.present(release, allowSkip: false)
                    } label: {
                        Label("MecoScribe \(release.version) is available", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.link)
                    .padding(.bottom, 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : .clear)
                    .padding(16)
            }

            Divider()

            RecentTranscriptsList(workspace: workspace)
                .frame(width: 300)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            FileDrop.loadFirstURL(from: providers) { url in
                workspace.open(url)
            }
        }
    }
}

private struct RecentTranscriptsList: View {
    let workspace: Workspace
    private var recents: [URL] { AppModel.shared.recentFiles }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent Transcripts")
                    .font(.headline)
                Spacer()
                if !recents.isEmpty {
                    Button("Clear") { AppModel.shared.clearRecents() }
                        .buttonStyle(.borderless)
                        .help("Remove all recent transcripts from this list")
                }
            }
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 8)
            if recents.isEmpty {
                ContentUnavailableView(
                    "No Recent Transcripts",
                    systemImage: "clock",
                    description: Text("Transcripts you open or create appear here.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(recents, id: \.self) { url in
                    RecentTranscriptRow(url: url) {
                        workspace.open(url)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background.secondary)
    }
}

private struct RecentTranscriptRow: View {
    let url: URL
    let open: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .lineLimit(1)
                    Text(url.deletingLastPathComponent().path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                AppModel.shared.removeRecent(url)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from Recent Transcripts")
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .accessibilityHidden(!isHovering)
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Remove from Recents") {
                AppModel.shared.removeRecent(url)
            }
        }
    }
}

enum FileDrop {
    /// Loads the first file URL from a drop and calls `handler` on the main actor.
    static func loadFirstURL(from providers: [NSItemProvider], handler: @escaping @MainActor (URL) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) else {
            return false
        }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.isFileURL else { return }
            Task { @MainActor in handler(url) }
        }
        return true
    }
}
