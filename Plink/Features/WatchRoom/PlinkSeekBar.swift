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
                Capsule().fill(.white.opacity(0.15)).frame(height: isScrubbing ? 4 : 2)
                Capsule().fill(.white.opacity(0.25)).frame(width: loaded, height: isScrubbing ? 4 : 2)
                Capsule().fill(PlinkRave.timeline).frame(width: played, height: isScrubbing ? 4 : 2)
                Circle()
                    .fill(.white)
                    .frame(width: isScrubbing ? 16 : 10, height: isScrubbing ? 16 : 10)
                    .offset(x: max(0, min(width - (isScrubbing ? 16 : 10), played - 5)))
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
        .frame(height: 24)
        .opacity(enabled ? 1 : 0.5)
    }
}
