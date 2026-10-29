import MecoScribeCore
import SwiftUI

struct PlayerBar: View {
    let player: AudioPlayerModel
    @AppStorage(Preferences.followPlayback) private var followPlayback = false
    @AppStorage(Preferences.showVideo) private var showVideo = true
    @State private var scrubTime: Double?

    static func rateLabel(_ rate: Float) -> String {
        rate == 1 ? "1×" : "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.skip(by: -5)
            } label: {
                Image(systemName: "gobackward.5")
            }
            .help("Back 5 seconds (⌥⌘←)")

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .help("Play/Pause (Space)")

            Button {
                player.skip(by: 5)
            } label: {
                Image(systemName: "goforward.5")
            }
            .help("Forward 5 seconds (⌥⌘→)")

            Text(TextExporter.formatTime(scrubTime ?? player.currentTime))
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { scrubTime ?? player.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(player.duration, 0.1)
            ) { editing in
                if !editing, let scrubTime {
                    player.seek(to: scrubTime, precise: true)
                    self.scrubTime = nil
                }
            }
            .controlSize(.small)

            Text(TextExporter.formatTime(player.duration))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .leading)

            Menu {
                ForEach(AudioPlayerModel.rates, id: \.self) { rate in
                    Button {
                        player.rate = rate
                    } label: {
                        if player.rate == rate {
                            Label(Self.rateLabel(rate), systemImage: "checkmark")
                        } else {
                            Text(Self.rateLabel(rate))
                        }
                    }
                }
            } label: {
                Text(Self.rateLabel(player.rate))
                    .monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Playback speed")

            if player.hasVideo {
                Toggle(isOn: $showVideo) {
                    Image(systemName: showVideo ? "play.rectangle.fill" : "play.rectangle")
                }
                .toggleStyle(.button)
                .help(showVideo ? "Hide video (⌥⌘V)" : "Show video (⌥⌘V)")
            }

            Toggle(isOn: $followPlayback) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
            }
            .toggleStyle(.button)
            .help("Follow playback: keep the spoken line in view")
        }
        .buttonStyle(.borderless)
        .disabled(!player.hasAudio)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
