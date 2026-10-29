import AVFoundation
import SwiftUI

/// Shows the video of a video source above the transcript. Playback is driven by the
/// player bar; clicking the picture plays or pauses.
struct VideoPane: View {
    let player: AudioPlayerModel

    var body: some View {
        PlayerLayerView(player: player.player)
            .aspectRatio(player.videoSize ?? CGSize(width: 16, height: 9), contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .contentShape(Rectangle())
            .onTapGesture { player.togglePlayPause() }
            .accessibilityLabel("Video")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Plays or pauses")
    }
}

/// A bar between the video and the transcript; drag it to resize the video.
struct VideoResizeHandle: View {
    @Binding var height: Double
    let range: ClosedRange<Double>
    @State private var startHeight: Double?

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = startHeight ?? height
                        startHeight = start
                        height = min(max(start + value.translation.height, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in startHeight = nil }
            )
            .accessibilityLabel("Video height")
            .accessibilityValue("\(Int(height)) points")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 40.0 : -40.0
                height = min(max(height + step, range.lowerBound), range.upperBound)
            }
    }
}

/// An `AVPlayerLayer` host. No built-in controls, so the player bar stays the only transport.
private struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerNSView {
        let view = PlayerLayerNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerLayerNSView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

final class PlayerLayerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
