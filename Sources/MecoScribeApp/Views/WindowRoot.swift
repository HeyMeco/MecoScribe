import SwiftUI

struct WindowRoot: View {
    static let sceneID = "main"

    @State private var workspace = Workspace()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        content
            .frame(minWidth: 760, minHeight: 560)
            .focusedSceneValue(\.workspace, workspace)
            .onAppear {
                if let request = AppModel.shared.takePendingRequest() {
                    workspace.handle(request)
                }
            }
            .onOpenURL { url in
                guard url.isFileURL else { return }
                if workspace.isIdle {
                    workspace.open(url)
                } else {
                    AppModel.shared.enqueue(.open(url))
                    openWindow(id: Self.sceneID)
                }
            }
            .onDisappear {
                workspace.closeCurrent()
            }
            .alert(
                "Could not open file",
                isPresented: Binding(
                    get: { workspace.errorMessage != nil },
                    set: { if !$0 { workspace.errorMessage = nil } }
                ),
                presenting: workspace.errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch workspace.phase {
        case .welcome:
            WelcomeView(workspace: workspace)
                .navigationTitle("MecoScribe")
        case .setup(let setup):
            NewTranscriptionView(workspace: workspace, setup: setup)
                .navigationTitle("New Transcription")
        case .transcribing(let job):
            TranscriptionProgressView(workspace: workspace, job: job)
                .navigationTitle("Transcribing \(job.request.audioURL.lastPathComponent)")
        case .editor(let editor):
            EditorView(model: editor) { workspace.closeProject() }
                .id(ObjectIdentifier(editor))
        }
    }
}
