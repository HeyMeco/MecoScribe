import MecoScribeCore
import SwiftUI

struct PlayerPanelView: View {
    @Bindable var player: AudioPlaybackModel
    @Binding var editMode: EditorEditMode
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: { player.togglePlayback() }) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)

                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 0.01)
                )

                Text("\(TranscriptFormatting.formatTime(player.currentTime)) / \(TranscriptFormatting.formatTime(player.duration))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 110, alignment: .trailing)

                Picker("Speed", selection: $player.playbackRate) {
                    Text("0.75×").tag(Float(0.75))
                    Text("1×").tag(Float(1.0))
                    Text("1.25×").tag(Float(1.25))
                    Text("1.5×").tag(Float(1.5))
                    Text("2×").tag(Float(2.0))
                }
                .pickerStyle(.menu)
                .frame(width: 80)
            }

            HStack {
                Picker("Edit Mode", selection: $editMode) {
                    ForEach(EditorEditMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Text(editMode == .assign ? "Select words, then assign a speaker." : "Drag words to reorder them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Undo", action: onUndo)
                    .disabled(!canUndo)
                    .keyboardShortcut("z")
                Button("Redo", action: onRedo)
                    .disabled(!canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}
