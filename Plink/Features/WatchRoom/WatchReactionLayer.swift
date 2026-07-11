import SwiftUI

struct WatchReactionLayer: View {
    let reactions: [WatchReactionEvent]
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(reactions.suffix(5)) { reaction in
                    Text(reaction.emoji)
                        .font(.system(size: reduceMotion ? 26 : 36))
                        .position(
                            x: reduceMotion ? proxy.size.width - 40 : reaction.startX * proxy.size.width,
                            y: reduceMotion ? 90 : reaction.currentY(in: proxy.size.height)
                        )
                        .opacity(reaction.opacity)
                        .scaleEffect(reaction.scale)
                        .rotationEffect(.degrees(reduceMotion ? 0 : reaction.rotation))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
