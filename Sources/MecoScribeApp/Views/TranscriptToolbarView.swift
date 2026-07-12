import MecoScribeCore
import SwiftUI

struct TranscriptToolbarView: View {
    @Bindable var document: TranscriptDocument
    let onSave: () -> Void
    let onDiscard: () -> Void
    let onExportTXT: () -> Void
    let onExportHTML: () -> Void
    let onClose: () -> Void
    let onRetranscribe: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Save Now", action: onSave)
                .keyboardShortcut("s")
            Button("Discard Edits", action: onDiscard)
            Divider().frame(height: 20)
            Button("Export .txt", action: onExportTXT)
            Button("Export HTML", action: onExportHTML)
            Button("Re-transcribe", action: onRetranscribe)
            Spacer()
            saveStatusLabel
            Button("Close", action: onClose)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var saveStatusLabel: some View {
        switch document.saveStatus {
        case .saved(let date):
            Text("Saved \(date.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .dirty:
            Text("Unsaved changes")
                .font(.caption)
                .foregroundStyle(.orange)
        case .saving:
            Text("Saving…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .error(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
