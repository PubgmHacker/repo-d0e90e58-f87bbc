// Plink/Features/AI/PlinkAIMeshView.swift — GPT-5.6 §10
import SwiftUI

struct PlinkAIMeshView: View {
    let state: PlinkAIVisualState
    let theme: PlinkLivingTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 1.0 / 30.0)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                AIMeshRenderer.draw(context: &context, size: size,
                    time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate,
                    state: state, theme: theme)
            }
        }
        .accessibilityHidden(true)
        .accessibilityLabel(state.rawValue)
    }
}

enum AIMeshRenderer {
    static func draw(context: inout GraphicsContext, size: CGSize, time: TimeInterval, state: PlinkAIVisualState, theme: PlinkLivingTheme) {
        let cx = size.width / 2; let cy = size.height / 2
        let baseColor = theme.colors[2].color
        let speed: Double = switch state { case .idle: 0.15; case .listening: 0.6; case .thinking: 0.4; case .speaking: 0.5; case .moderating: 0.1; default: 0.15 }
        let rings = 22
        for i in 0..<rings {
            let r = 20.0 + Double(i) * 8.0
            let wobble = sin(time * speed + Double(i) * 0.5) * 6.0
            let path = Path { p in
                for j in 0...32 {
                    let angle = Double(j) / 32.0 * .pi * 2
                    let dist = r + sin(angle * 6 + time * speed + Double(i)) * wobble
                    let x = cx + cos(angle) * dist
                    let y = cy + sin(angle) * dist
                    if j == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
                p.closeSubpath()
            }
            context.opacity = 0.04 + 0.06 * (1.0 - Double(i) / Double(rings))
            context.stroke(path, with: .color(baseColor), lineWidth: 1)
        }
    }
}
