import AppKit
import MecoScribeCore
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("MecoScribe")
                .font(.largeTitle.bold())

            Text("Diarized transcription with an interactive editor")
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button("Open Audio…") { pickAudio() }
                    .keyboardShortcut("o")
                Button("Open Transcript…") { pickTranscript() }
                Button("Settings…") { appModel.showSettings = true }
            }

            Text("Drop an audio or transcript file here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .sheet(isPresented: Binding(
            get: { appModel.showSettings },
            set: { appModel.showSettings = $0 }
        )) {
            SettingsView(settings: appModel.settings)
        }
    }

    private func pickAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mpeg4Audio, .wav, .mp3]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            appModel.openAudio(url: url)
        }
    }

    private func pickTranscript() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            appModel.openTranscript(url: url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil)
            else { return }

            DispatchQueue.main.async {
                let ext = url.pathExtension.lowercased()
                if ext == "txt" {
                    appModel.openTranscript(url: url)
                } else {
                    appModel.openAudio(url: url)
                }
            }
        }
        return true
    }
}
