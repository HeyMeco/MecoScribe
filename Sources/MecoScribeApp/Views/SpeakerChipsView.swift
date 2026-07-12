import MecoScribeCore
import SwiftUI

struct SpeakerChipsView: View {
    @Bindable var document: TranscriptDocument
    let onRename: (String) -> Void
    let onDelete: (String) -> Void
    let onAdd: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(document.state.speakerIds, id: \.self) { speakerId in
                    SpeakerChipView(
                        speakerId: speakerId,
                        name: SpeakerPalette.displayName(for: speakerId, speakerNames: document.state.speakerNames),
                        colorHex: SpeakerPalette.color(for: speakerId, speakerIds: document.state.speakerIds),
                        onRename: { onRename(speakerId) },
                        onDelete: { onDelete(speakerId) }
                    )
                }
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

struct SpeakerChipView: View {
    let speakerId: String
    let name: String
    let colorHex: String
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: colorHex))
                .frame(width: 10, height: 10)
            Text(name)
                .font(.caption.weight(.medium))
            Button("Rename", action: onRename)
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .contextMenu {
            Button("Rename…", action: onRename)
            Button("Delete Speaker…", role: .destructive, action: onDelete)
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
