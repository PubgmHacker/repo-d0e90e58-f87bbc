import SwiftUI
import UIKit

// MARK: - PlayerSlotView (v90 — SwiftUI frame proxy)
//
// 🔧 v90 (Gemini): Transparent SwiftUI view that DOES NOT contain the player.
// It only reports its frame to PlayerWindowContainer via layoutSubviews().
// Think of it as a "hole" in the SwiftUI layout through which the
// UIWindow-hosted AVPlayerLayer is visible.
//
// SwiftUI manages this view's lifecycle (create/destroy/move),
// but since it doesn't contain the actual player, SwiftUI CANNOT
// kill, recreate, or interrupt AVPlayer.

struct PlayerSlotView: UIViewRepresentable {
    func makeUIView(context: Context) -> PlayerSlotUIView {
        let view = PlayerSlotUIView()
        view.onFrameChange = { globalFrame in
            // Convert global frame to PlayerWindowContainer's coordinate space
            // (player window covers full screen, so global = window coordinates)
            PlayerWindowContainer.shared.updateFrame(globalFrame)
        }
        return view
    }

    func updateUIView(_ uiView: PlayerSlotUIView, context: Context) {
        // Force frame update on SwiftUI re-evaluation
        uiView.layoutSubviews()
    }

    static func dismantleUIView(_ uiView: PlayerSlotUIView, coordinator: ()) {
        // When SwiftUI removes this view (leaving room), hide the player window
        PlayerWindowContainer.shared.hide()
    }
}

// MARK: - PlayerSlotUIView
//
/// UIView that monitors its own frame changes via layoutSubviews.
/// Fires onFrameChange callback on every layout pass (rotation, scroll, etc.)
/// This is more reliable than GeometryReader (which can cause layout cycles).

final class PlayerSlotUIView: UIView {
    var onFrameChange: ((CGRect) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Convert self.bounds to global (window) coordinates
        guard window != nil else { return }
        let globalFrame = self.convert(self.bounds, to: nil)
        onFrameChange?(globalFrame)
    }

    // Also update on first appearance (didMoveToWindow)
    override func didMoveToWindow() {
        super.didMoveToWindow()
        layoutSubviews()
    }
}
