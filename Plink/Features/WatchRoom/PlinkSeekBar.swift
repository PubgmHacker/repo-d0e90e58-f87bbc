import SwiftUI

struct PlinkSeekBar: View {
    @Binding var value: Double
    let buffered: Double
    let duration: Double
    @Binding var isScrubbing: Bool
    let enabled: Bool
    let onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let played = CGFloat(max(0, min(1, value / duration))) * width
            let loaded = CGFloat(max(0, min(1, buffered))) * width

            ZStack(alignment: .leading) {
                Capsule().fill(PlinkRave.divider.opacity(0.45)).frame(height: isScrubbing ? 5 : 3)
                Capsule().fill(Color(hex: 0xD8B4FE).opacity(0.42)).frame(width: loaded, height: isScrubbing ? 5 : 3)
                Capsule().fill(PlinkRave.timeline).frame(width: played, height: isScrubbing ? 5 : 3)
                Circle()
                    .fill(PlinkRave.cyan)
                    .frame(width: isScrubbing ? 22 : 14, height: isScrubbing ? 22 : 14)
                    .plinkGlow(PlinkRave.cyan, radius: isScrubbing ? 12 : 7)
                    .offset(x: max(0, min(width - (isScrubbing ? 22 : 14), played - 7)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard enabled else { return }
                        isScrubbing = true
                        value = max(0, min(duration, Double(gesture.location.x / width) * duration))
                    }
                    .onEnded { _ in
                        guard enabled else { return }
                        isScrubbing = false
                        onCommit(value)
                    }
            )
        }
        .frame(height: 26)
        .opacity(enabled ? 1 : 0.7)
    }
}
