import MecoScribeCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if let document = appModel.document {
                TranscriptEditorView(document: document)
            } else if appModel.transcriptionPhase != .idle {
                TranscriptionProgressView()
            } else {
                WelcomeView()
            }
        }
        .alert("Error", isPresented: .init(
            get: { appModel.errorMessage != nil },
            set: { if !$0 { appModel.errorMessage = nil } }
        )) {
            Button("OK") { appModel.errorMessage = nil }
        } message: {
            Text(appModel.errorMessage ?? "")
        }
        .onChange(of: appModel.fileWatcher?.hasExternalChange) { _, changed in
            if changed == true {
                appModel.showConflictAlert = true
            }
        }
        .alert("File Changed Externally", isPresented: Binding(
            get: { appModel.showConflictAlert },
            set: { appModel.showConflictAlert = $0 }
        )) {
            Button("Reload from Disk") {
                appModel.handleExternalConflict(action: .reload)
            }
            Button("Keep Local Edits", role: .cancel) {
                appModel.handleExternalConflict(action: .keepLocal)
            }
        } message: {
            Text("The transcript file was modified outside MecoScribe.")
        }
    }
}
