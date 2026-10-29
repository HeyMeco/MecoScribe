import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AudioPlayerModel {
    static let rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPlaying = false
    private(set) var hasAudio = false
    /// Display size of the video track, or nil when the media has no video.
    private(set) var videoSize: CGSize?

    var hasVideo: Bool { videoSize != nil }

    var rate: Float {
        didSet {
            player.defaultRate = rate
            if isPlaying { player.rate = rate }
            UserDefaults.standard.set(Double(rate), forKey: Preferences.playbackRate)
        }
    }

    /// Called on every time tick and seek, so the editor can update word highlighting.
    @ObservationIgnored var onTimeChange: ((Double) -> Void)?

    /// The underlying player; the video pane renders from it.
    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private nonisolated(unsafe) var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    init(fallbackDuration: Double) {
        duration = fallbackDuration
        let storedRate = UserDefaults.standard.double(forKey: Preferences.playbackRate)
        rate = storedRate > 0 ? Float(storedRate) : 1
        player.defaultRate = rate

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.timeDidChange(time.seconds)
            }
        }

        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in
                self?.isPlaying = playing
            }
        }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        player.pause()
    }

    func load(url: URL?) {
        player.pause()
        videoSize = nil
        guard let url else {
            player.replaceCurrentItem(with: nil)
            hasAudio = false
            return
        }
        let asset = AVURLAsset(url: url)
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        hasAudio = true
        Task { [weak self] in
            if let loaded = try? await asset.load(.duration), loaded.seconds.isFinite, loaded.seconds > 0 {
                self?.duration = loaded.seconds
            }
            let size = await Self.videoSize(of: asset)
            guard let self, self.player.currentItem?.asset === asset else { return }
            self.videoSize = size
        }
    }

    /// Display size of the first video track (rotation applied), or nil for audio.
    private nonisolated static func videoSize(of asset: AVURLAsset) async -> CGSize? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
            let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform)
        else { return nil }
        let rect = CGRect(origin: .zero, size: natural).applying(transform)
        let size = CGSize(width: abs(rect.width), height: abs(rect.height))
        return size.width > 0 && size.height > 0 ? size : nil
    }

    func togglePlayPause() {
        guard hasAudio else { return }
        if isPlaying {
            player.pause()
        } else {
            if duration > 0, currentTime >= duration - 0.05 {
                seek(to: 0)
            }
            player.playImmediately(atRate: rate)
        }
    }

    func pause() {
        player.pause()
    }

    func play(from seconds: Double) {
        guard hasAudio else { return }
        seek(to: seconds, precise: true)
        player.playImmediately(atRate: rate)
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds, precise: true)
    }

    func seek(to seconds: Double, precise: Bool = false) {
        let clamped = max(0, duration > 0 ? min(seconds, duration) : seconds)
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        if precise {
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.seek(to: time)
        }
        timeDidChange(clamped)
    }

    private func timeDidChange(_ seconds: Double) {
        guard seconds.isFinite else { return }
        currentTime = seconds
        onTimeChange?(seconds)
    }
}
