import AppKit
import MecoScribeCore
import SwiftUI

@main
struct MecoScribeApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .frame(minWidth: 900, minHeight: 700)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Audio…") { openAudio() }
                    .keyboardShortcut("o")
                Button("Open Transcript…") { openTranscript() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(settings: appModel.settings)
        }
    }

    private func openAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mpeg4Audio, .wav]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            appModel.openAudio(url: url)
        }
    }

    private func openTranscript() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            appModel.openTranscript(url: url)
        }
    }
}
