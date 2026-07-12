import MecoScribeCore
import SwiftUI

struct TranscriptHeaderView: View {
    @Bindable var document: TranscriptDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.audioURL.lastPathComponent)
                .font(.title2.bold())
            HStack(spacing: 16) {
                Label(document.state.audioFile, systemImage: "doc")
                Label(TranscriptFormatting.formatTime(document.state.durationSeconds), systemImage: "clock")
                Label("\(document.state.speakerIds.count) speakers", systemImage: "person.2")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("Click a word to seek · Double-click utterance to edit · ⌘Z undo")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
