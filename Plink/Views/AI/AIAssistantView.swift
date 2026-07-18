// Plink/Views/AI/AIAssistantView.swift — premium AI entry point
import SwiftUI

struct AIAssistantView: View {
    @State private var input = ""
    @State private var orbState: AssistantOrbState = .idle

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            LocalSiriGlowingOrbView(state: orbState, size: 210)
                .frame(width: 300, height: 300)
                .padding(.bottom, 4)

            VStack(spacing: 8) {
                Text("Plink AI")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(aiText)
                Text(stateCaption)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(stateColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(stateColor.opacity(0.12), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Кинокомпаньон")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(aiText)
                Text("Соберу очередь, помогу выбрать видео, подскажу что смотрят друзья и создам комнату после подтверждения.")
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundStyle(aiSecondary)
            }
            .padding(16)
            .background(aiSurface.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.08)))
            .padding(.horizontal, 18)
            .padding(.top, 26)

            HStack(spacing: 8) {
                chip("Очередь", state: .thinking)
                chip("Слушать", state: .listening)
                chip("Ответ", state: .speaking)
            }
            .padding(.top, 16)

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                Button {
                    setTemporaryState(.listening)
                } label: {
                    Image(systemName: orbState == .listening ? "mic.fill" : "mic")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(orbState == .listening ? .black : aiText)
                }
                .frame(width: 44, height: 44)
                .background(orbState == .listening ? stateColor : aiSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                TextField("Спроси про фильмы и комнаты", text: $input)
                    .font(.system(size: 14))
                    .foregroundStyle(aiText)
                    .onChange(of: input) { _, newValue in
                        orbState = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .idle : .listening
                    }

                Button {
                    input = ""
                    setTemporaryState(.thinking, then: .speaking)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                }
                .frame(width: 44, height: 44)
                .background(aiAccent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.10)))
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(aiBackground.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .preferredColorScheme(.dark)
    }

    private var aiBackground: Color { Color(red: 0.035, green: 0.04, blue: 0.06) }
    private var aiSurface: Color { Color(red: 0.10, green: 0.12, blue: 0.17) }
    private var aiText: Color { Color.white.opacity(0.94) }
    private var aiSecondary: Color { Color.white.opacity(0.62) }
    private var aiAccent: Color { Color(red: 0.20, green: 0.82, blue: 0.92) }

    private var stateCaption: String {
        switch orbState {
        case .idle: return "Готов помочь"
        case .listening: return "Слушаю…"
        case .thinking: return "Думаю…"
        case .speaking: return "Отвечаю…"
        }
    }

    private var stateColor: Color {
        switch orbState {
        case .idle: return Color(red: 0.35, green: 0.70, blue: 1.0)
        case .listening: return Color(red: 0.25, green: 0.92, blue: 1.0)
        case .thinking: return Color(red: 1.0, green: 0.30, blue: 0.88)
        case .speaking: return Color(red: 0.28, green: 1.0, blue: 0.72)
        }
    }

    private func chip(_ title: String, state: AssistantOrbState) -> some View {
        Button {
            setTemporaryState(state)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(aiText)
                .padding(.horizontal, 13)
                .frame(height: 36)
                .background(aiSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func setTemporaryState(_ state: AssistantOrbState, then next: AssistantOrbState? = nil) {
        orbState = state
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.15))
            if let next {
                orbState = next
                try? await Task.sleep(for: .seconds(1.7))
            }
            if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                orbState = .idle
            }
        }
    }
}

private enum AssistantOrbState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
}

private struct LocalSiriGlowingOrbView: View {
    let state: AssistantOrbState
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [primary.opacity(glowOpacity), secondary.opacity(0.22), .clear], center: .center, startRadius: size * 0.08, endRadius: size * 0.82))
                    .frame(width: size * 1.45, height: size * 1.45)
                    .blur(radius: size * 0.08)

                Canvas { ctx, canvasSize in
                    let rect = CGRect(origin: .zero, size: canvasSize)
                    let center = CGPoint(x: rect.midX, y: rect.midY)
                    let radius = min(canvasSize.width, canvasSize.height) * 0.43
                    let body = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

                    ctx.addFilter(.blur(radius: state == .idle ? 8 : 11))
                    for i in 0..<7 {
                        let fi = Double(i)
                        let angle = t * speed * (0.65 + fi * 0.11) + fi * .pi * 0.44
                        let wobble = radius * (0.12 + 0.035 * sin(t * 1.7 + fi))
                        let blobCenter = CGPoint(x: center.x + cos(angle) * wobble, y: center.y + sin(angle * 1.23) * wobble)
                        let blobRadius = radius * CGFloat(0.58 + 0.12 * sin(t * 2.1 + fi))
                        let color = [primary, secondary, Color.white.opacity(0.82), primary][i % 4]
                        ctx.fill(Path(ellipseIn: CGRect(x: blobCenter.x - blobRadius, y: blobCenter.y - blobRadius, width: blobRadius * 2, height: blobRadius * 2)), with: .radialGradient(Gradient(colors: [color.opacity(0.95), color.opacity(0)]), center: blobCenter, startRadius: 0, endRadius: blobRadius))
                    }

                    ctx.addFilter(.blur(radius: 0))
                    ctx.clip(to: body)
                    ctx.fill(body, with: .radialGradient(Gradient(colors: [Color.white.opacity(0.48), primary.opacity(0.7), secondary.opacity(0.58), deep.opacity(0.88)]), center: CGPoint(x: center.x - radius * 0.25, y: center.y - radius * 0.28), startRadius: 0, endRadius: radius * 1.35))
                    ctx.stroke(body, with: .color(Color.white.opacity(0.30)), lineWidth: 1.4)
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .shadow(color: primary.opacity(0.55), radius: size * 0.10)
                .shadow(color: secondary.opacity(0.32), radius: size * 0.20)

                Circle()
                    .stroke(AngularGradient(colors: [.clear, primary, secondary, Color.white.opacity(0.8), primary, .clear], center: .center), lineWidth: state == .idle ? 1.2 : 2.4)
                    .frame(width: size * 1.08, height: size * 1.08)
                    .rotationEffect(.degrees(t * rotation * 20))
                    .opacity(state == .idle ? 0.42 : 0.85)

                Ellipse()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.72), Color.white.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size * 0.42, height: size * 0.25)
                    .offset(x: -size * 0.17, y: -size * 0.23)
                    .rotationEffect(.degrees(-24 + sin(t * 0.7) * 4))
                    .blur(radius: 1.1)

                if state != .idle {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(primary.opacity(0.32 - Double(i) * 0.07), lineWidth: 1.6)
                            .frame(width: size * (1.08 + CGFloat(i) * 0.18 + CGFloat(max(0, sin(t * speed + Double(i))) * 0.08)), height: size * (1.08 + CGFloat(i) * 0.18 + CGFloat(max(0, sin(t * speed + Double(i))) * 0.08)))
                            .blur(radius: CGFloat(i) * 0.8)
                    }
                }
            }
            .frame(width: size * 1.55, height: size * 1.55)
            .scaleEffect(1 + CGFloat((sin(t * speed) + 1) * 0.5) * scale)
        }
    }

    private var primary: Color {
        switch state {
        case .idle: return Color(red: 0.20, green: 0.76, blue: 1.0)
        case .listening: return Color(red: 0.15, green: 0.92, blue: 1.0)
        case .thinking: return Color(red: 1.0, green: 0.25, blue: 0.86)
        case .speaking: return Color(red: 0.28, green: 1.0, blue: 0.72)
        }
    }
    private var secondary: Color {
        switch state {
        case .idle: return Color(red: 0.43, green: 0.28, blue: 1.0)
        case .listening: return Color(red: 1.0, green: 0.27, blue: 0.82)
        case .thinking: return Color(red: 0.24, green: 0.82, blue: 1.0)
        case .speaking: return Color(red: 0.20, green: 0.66, blue: 1.0)
        }
    }
    private var deep: Color {
        switch state {
        case .idle: return Color(red: 0.08, green: 0.05, blue: 0.30)
        case .listening: return Color(red: 0.06, green: 0.08, blue: 0.42)
        case .thinking: return Color(red: 0.22, green: 0.03, blue: 0.38)
        case .speaking: return Color(red: 0.03, green: 0.25, blue: 0.24)
        }
    }
    private var speed: Double {
        switch state {
        case .idle: return 0.85
        case .listening: return 2.1
        case .thinking: return 3.4
        case .speaking: return 2.7
        }
    }
    private var rotation: Double {
        switch state {
        case .idle: return 0.55
        case .listening: return 1.25
        case .thinking: return 2.2
        case .speaking: return 1.75
        }
    }
    private var glowOpacity: Double { state == .idle ? 0.46 : 0.70 }
    private var scale: CGFloat { state == .idle ? 0.035 : state == .thinking ? 0.10 : 0.08 }
}
