@preconcurrency import AVFoundation
import Foundation
import MecoScribeCore
import Observation

struct PlaybackHighlight: Equatable, Sendable {
    let utteranceIndex: Int
    let wordIndex: Int?
}

@MainActor
@Observable
final class AudioPlaybackModel {
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var playbackHighlight: PlaybackHighlight?
    var playbackRate: Float = 1.0 {
        didSet { player?.rate = isPlaying ? playbackRate : 0 }
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var trackedUtterances: [DiarizedUtterance] = []

    func trackUtterances(_ utterances: [DiarizedUtterance]) {
        trackedUtterances = utterances
        refreshPlaybackHighlight()
    }

    func load(url: URL) {
        stop()
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player?.automaticallyWaitsToMinimizeStalling = false

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isPlaying = false }
        }

        Task { @MainActor in
            if let loadedDuration = try? await item.asset.load(.duration) {
                duration = CMTimeGetSeconds(loadedDuration)
            }
        }

        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = CMTimeGetSeconds(time)
                self.refreshPlaybackHighlight()
            }
        }
    }

    func play() {
        player?.rate = playbackRate
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: TimeInterval) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
        refreshPlaybackHighlight()
    }

    func playFrom(_ seconds: TimeInterval) {
        seek(to: seconds)
        play()
    }

    func stop() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        timeObserver = nil
        endObserver = nil
        player?.pause()
        player = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        playbackHighlight = nil
        trackedUtterances = []
    }

    private func refreshPlaybackHighlight() {
        let time = currentTime
        var newHighlight: PlaybackHighlight?

        for (index, utterance) in trackedUtterances.enumerated() {
            guard time >= utterance.startTime - 0.05, time <= utterance.endTime + 0.15 else { continue }
            let wordIndex = utterance.words.firstIndex { word in
                time >= word.startTime - 0.05 && time <= word.endTime + 0.15
            }
            newHighlight = PlaybackHighlight(utteranceIndex: index, wordIndex: wordIndex)
            break
        }

        if playbackHighlight != newHighlight {
            playbackHighlight = newHighlight
        }
    }
}
