import UIKit
import AVFoundation

// MARK: - PlayerWindowContainer (v90 — God-Mode UIWindow)
//
// 🔧 v90 (Gemini): Separate UIWindow that hosts AVPlayerLayer.
// This window lives ABOVE the main app window (windowLevel = .normal + 1).
// SwiftUI CANNOT touch, remove, or recreate this window.
// AVPlayerLayer stays alive across navigation, background, shade open/close.
//
// Lifecycle:
//   - Created once (singleton) at app launch
//   - show() when entering room (window.isHidden = false)
//   - hide() when leaving room (window.isHidden = true)
//   - Player keeps playing in background (AVAudioSession .playback)
//   - PiP starts automatically when app backgrounds

@MainActor
final class PlayerWindowContainer {
    static let shared = PlayerWindowContainer()

    /// The UIWindow that hosts the player. Lives for the entire app lifetime.
    private let window: UIWindow

    /// Root VC of the player window — just a transparent container.
    private let rootVC: UIViewController

    /// The AVPlayerLayer — the actual video rendering surface.
    /// Frame is updated by PlayerSlotView (SwiftUI proxy) via updateFrame().
    let playerLayer: AVPlayerLayer

    /// Track if window is currently shown
    private(set) var isShown = false

    private init() {
        // Create window — will be assigned to the active scene in show()
        window = UIWindow()
        window.windowLevel = .normal + 1  // Above main app window
        window.backgroundColor = .clear
        window.isHidden = true  // Hidden until player is needed

        rootVC = UIViewController()
        rootVC.view.backgroundColor = .clear
        window.rootViewController = rootVC

        // AVPlayerLayer — added to rootVC.view.layer
        playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = UIColor.black.cgColor
        rootVC.view.layer.addSublayer(playerLayer)

        print("🪟 v90: PlayerWindowContainer initialized (UIWindow created)")
    }

    // MARK: - Show / Hide

    /// Show the player window. Called when entering room.
    /// Finds the active UIWindowScene and attaches the player window to it.
    func show() {
        guard !isShown else { return }

        // Find the active window scene (iOS 13+)
        let activeScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene

        if let scene = activeScene {
            window.windowScene = scene
        }

        window.isHidden = false
        isShown = true
        print("🪟 v90: PlayerWindowContainer SHOW — window visible")
    }

    /// Hide the player window. Called when leaving room.
    /// DON'T destroy — player keeps playing in background if needed.
    func hide() {
        guard isShown else { return }
        window.isHidden = true
        isShown = false
        print("🪟 v90: PlayerWindowContainer HIDE — window hidden (player preserved)")
    }

    // MARK: - Player Management

    /// Set the AVPlayer on the player layer.
    func setPlayer(_ player: AVPlayer) {
        playerLayer.player = player
        print("🪟 v90: AVPlayer set on playerLayer")
    }

    /// Update the player layer frame to match the SwiftUI slot position.
    /// Called by PlayerSlotView.layoutSubviews() on every layout pass.
    func updateFrame(_ rect: CGRect) {
        // The player window covers the whole screen, so global coordinates
        // = window coordinates (same coordinate space).
        guard playerLayer.frame != rect else { return }
        playerLayer.frame = rect
    }

    /// Get the player layer's current frame (for PiP controller setup).
    var playerLayerFrame: CGRect {
        return playerLayer.frame
    }
}
