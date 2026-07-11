import SwiftUI

struct PurpleAmbientBackdrop: View {
    let primary: Color
    let secondary: Color

    init(primary: Color = PlinkRave.magenta, secondary: Color = PlinkRave.cyan) {
        self.primary = primary
        self.secondary = secondary
    }

    var body: some View {
        ZStack {
            PlinkRave.void
            RadialGradient(
                colors: [primary.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 4,
                endRadius: 320
            )
            RadialGradient(
                colors: [secondary.opacity(0.08), .clear],
                center: .bottomLeading,
                startRadius: 4,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
