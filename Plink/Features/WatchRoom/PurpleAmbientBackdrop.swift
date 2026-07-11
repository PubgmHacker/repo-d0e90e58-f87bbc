import SwiftUI

// Subtle ambient backdrop — NOT flashy neon.
// Deep warm dark with faint purple glow, like a cinema at night.

struct PurpleAmbientBackdrop: View {
    var body: some View {
        ZStack {
            PlinkRave.void
            // Very subtle top glow — barely visible, creates depth
            RadialGradient(
                colors: [PlinkRave.primary.opacity(0.05), .clear],
                center: .topTrailing,
                startRadius: 4,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
