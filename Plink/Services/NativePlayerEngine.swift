import AVFoundation
import AVKit
import UIKit
import Combine

// MARK: - NativePlayerEngine (v90 — God-Mode AVPlayer)
//
// 🔧 v90 (Gemini): Singleton AVPlayer that lives OUTSIDE SwiftUI.
// AVPlayer + AVPlayerLayer in PlayerWindowContainer's UIWindow.
// SwiftUI communicates via @Published properties (event-driven, not hierarchical).
//
// Background handling:
//   - AVAudioSession .playback → audio continues in background
//   - AVPictureInPictureController → PiP starts automatically on background
//   - No forceResumePlayback, no reactivate(), no JS hacks needed!
//   - AVPlayer manages its own decoder — iOS can't sterilize it like WKWebView

@MainActor
final class NativePlayerEngine: ObservableObject {
    static let shared = NativePlayerEngine()

    // MARK: - Published State (for SwiftUI)

    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying = false
    @Published var isLoading = false

    // MARK: - Private State

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var pipController: AVPictureInPictureController?
    private var statusObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?

    private init() {
        configureAudioSession()
    }

    // MARK: - AVAudioSession

    /// Configure AVAudioSession for background playback + PiP.
    /// .playback: audio continues when app is backgrounded
    /// .moviePlayback: optimized for video playback
    /// .mixWithOthers: don't interrupt other audio apps
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            print("🔊 v90: AVAudioSession configured (.playback + .moviePlayback)")
        } catch {
            print("⚠️ v90: AVAudioSession error: \(error)")
        }
    }

    // MARK: - Load & Play

    /// Load a stream URL and start playing.
    /// For googlevideo.com URLs, adds User-Agent + Referer headers.
    func loadAndPlay(streamURL: String) {
        guard let url = URL(string: streamURL) else {
            print("⚠️ v90: Invalid stream URL: \(streamURL.prefix(60))")
            return
        }

        isLoading = true
        print("🎬 v90: Loading stream: \(streamURL.prefix(80))")

        // Create asset with headers for googlevideo.com
        let lowerURL = streamURL.lowercased()
        let asset: AVAsset
        if lowerURL.contains("googlevideo.com") {
            let headers: [String: String] = [
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) " +
                              "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 " +
                              "Mobile/15E148 Safari/604.1",
                "Referer": "https://www.youtube.com/",
                "Origin": "https://www.youtube.com"
            ]
            let options: [String: Any] = [
                "AVURLAssetHTTPHeaderFieldsKey": headers,
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ]
            asset = AVURLAsset(url: url, options: options)
            print("🎬 v90: googlevideo.com URL — added User-Agent + Referer headers")
        } else {
            asset = AVURLAsset(url: url, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ])
        }

        let newItem = AVPlayerItem(asset: asset)

        // First time: create player + setup observers + PiP
        if player == nil {
            player = AVPlayer(playerItem: newItem)
            player?.automaticallyWaitsToMinimizeStalling = true
            player?.volume = 1.0
            player?.allowsExternalPlayback = true
            PlayerWindowContainer.shared.setPlayer(player!)
            setupPiP()
            addTimeObserver()
            observeStatus(newItem)
            observeDuration(newItem)
            print("🎬 v90: AVPlayer created (first time)")
        } else {
            // Subsequent loads: just replace item
            statusObservation?.invalidate()
            durationObservation?.invalidate()
            player?.replaceCurrentItem(with: newItem)
            observeStatus(newItem)
            observeDuration(newItem)
            print("🎬 v90: AVPlayer item replaced")
        }

        playerItem = newItem

        // Start playing
        player?.play()
        isPlaying = true
    }

    // MARK: - PiP

    /// Setup AVPictureInPictureController.
    /// Requires AVPlayerLayer to be visible in a view hierarchy (UIWindow).
    /// canStartPictureInPictureAutomaticallyFromInline = true → PiP starts
    /// automatically when app is backgrounded.
    private func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("📱 v90: PiP not supported on this device")
            return
        }

        pipController = AVPictureInPictureController(
            playerLayer: PlayerWindowContainer.shared.playerLayer
        )

        if let pip = pipController {
            if #available(iOS 14.2, *) {
                pip.canStartPictureInPictureAutomaticallyFromInline = true
            }
            pip.requiresLinearPlayback = false
            print("📱 v90: AVPictureInPictureController created — PiP ready")
        }
    }

    // MARK: - Playback Controls

    func play() {
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        currentTime = clamped
    }

    func seekRelative(_ delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    // MARK: - Attach / Detach (room lifecycle)

    /// Called when entering room. Shows the player window.
    func attach() {
        PlayerWindowContainer.shared.show()
        print("🎬 v90: NativePlayerEngine attached to room")
    }

    /// Called when leaving room. Hides the player window.
    /// Player is NOT destroyed — just hidden.
    func detach() {
        PlayerWindowContainer.shared.hide()
        pause()
        print("🎬 v90: NativePlayerEngine detached from room")
    }

    // MARK: - Time Observer

    private func addTimeObserver() {
        guard let player else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                if time.seconds.isFinite {
                    self.currentTime = time.seconds
                }
            }
        }
    }

    // MARK: - KVO Observers

    private func observeStatus(_ item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: .new) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
                    print("🎬 v90: AVPlayer ready to play — duration=\(self.duration)s")
                case .failed:
                    self.isLoading = false
                    print("⚠️ v90: AVPlayer failed: \(item.error?.localizedDescription ?? "unknown")")
                default:
                    break
                }
            }
        }
    }

    private func observeDuration(_ item: AVPlayerItem) {
        durationObservation = item.observe(\.duration, options: .new) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.duration.seconds.isFinite && item.duration.seconds > 0 {
                    self.duration = item.duration.seconds
                }
            }
        }
    }
}
