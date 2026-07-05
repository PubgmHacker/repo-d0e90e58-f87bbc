import SwiftUI

// MARK: - BioluminescentBackground — глубоководный туман
//
// Премиальный фон: 4 крупных размытых светящихся облака (blur 20-40pt),
// плавно дрейфующих по экрану.
//
// Производительность: Canvas + TimelineView (30fps cap) = GPU.
// 🔧 FIX 4.4: Рендеринг полностью останавливается когда приложение
// уходит в background (экономия батареи).
struct BioluminescentBackground: View {
    var energy: Double = 0.5
    var dimming: Double = 0
    var palette: BioPalette = .ocean

    // 🔧 FIX 4.4: Track app state to pause rendering in background
    @State private var isInBackground = false

    var body: some View {
        // 🔧 FIX 4.4: Use pausable timeline — renders only when in foreground
        Group {
            if !isInBackground {
                TimelineView(.animation(minimumInterval: 1.0/30.0)) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        drawDepth(context: context, size: size)
                        drawClouds(context: context, size: size, time: t)
                    }
                }
            } else {
                // Static frame when in background — just the base color
                Color.bioObsidian
            }
        }
        .overlay(
            // Затемнение под плеером
            LinearGradient(
                colors: [.clear, Color.bioObsidian.opacity(dimming * 0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
        .overlay(
            // Лёгкая зернистость для премиум-текстуры
            Canvas { context, size in
                drawNoise(context: context, size: size)
            }
            .opacity(0.025)
            .allowsHitTesting(false)
        )
        .ignoresSafeArea()
        // 🔧 FIX 4.4: Pause Canvas rendering when app goes to background
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            isInBackground = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            isInBackground = false
        }
    }

    // MARK: - Слои

    /// База — обсидиан.
    private func drawDepth(context: GraphicsContext, size: CGSize) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(Color.bioObsidian)
        )
    }

    /// 4 крупных биолюминесцентных облака — размытые, плавно дрейфующие.
    /// Pack v3: ускорено в 3x, облака в центре тоже, добавлены тёплые акценты.
    private func drawClouds(context: GraphicsContext, size: CGSize, time: Double) {
        let clouds: [(cx: Double, cy: Double, r: Double, speed: Double, phase: Double)] = [
            (0.2, 0.3, 280, 0.24, 0.0),   // верх-лево — большой cyan
            (0.8, 0.7, 240, 0.30, 1.5),   // низ-право — emerald
            (0.5, 0.5, 320, 0.20, 3.0),   // центр — крупный (тёплый accent)
            (0.15, 0.85, 200, 0.36, 4.5), // низ-лево — cyan
            (0.85, 0.2, 180, 0.28, 2.0),  // верх-право — тёплый accent
        ]

        for (i, cloud) in clouds.enumerated() {
            let dx = sin(time * cloud.speed + cloud.phase) * 80
            let dy = cos(time * cloud.speed * 0.7 + cloud.phase) * 60
            let cx = cloud.cx * size.width + dx
            let cy = cloud.cy * size.height + dy
            let radius = cloud.r * (0.9 + 0.15 * sin(time * 0.5 + cloud.phase))

            let color = palette.color(for: i)
            let pulse = 0.5 + 0.35 * sin(time * 0.6 + cloud.phase)
            let opacity = pulse * energy * 0.7

            let center = CGPoint(x: cx, y: cy)
            let rect = CGRect(
                x: cx - radius,
                y: cy - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(opacity), color.opacity(0)]),
                    center: .init(x: cx / size.width, y: cy / size.height),
                    startRadius: 0,
                    endRadius: radius
                )
            )
        }
    }

    /// Лёгкая зернистость (псевдо-noise) для премиум-текстуры.
    private func drawNoise(context: GraphicsContext, size: CGSize) {
        let stride: Double = 3
        var y: Double = 0
        var seed: UInt64 = 12345
        while y < size.height {
            var x: Double = 0
            while x < size.width {
                seed = (seed &* 1103515245 &+ 12345) & 0x7FFFFFFF
                let v = Double(seed % 100) / 100.0
                if v > 0.5 {
                    context.fill(
                        Path(CGRect(x: x, y: y, width: 1, height: 1)),
                        with: .color(.white)
                    )
                }
                x += stride
            }
            y += stride
        }
    }
}

// MARK: - Bio Palette
enum BioPalette {
    case ocean
    case abyss
    case coral

    func color(for index: Int) -> Color {
        let colors: [Color]
        switch self {
        case .ocean:
            // Pack v3: смешиваем холодные и тёплые для разнообразия
            colors = [Color.bioCyan, Color.bioEmerald, Color.bioAmber, Color.bioTeal, Color.bioCoral]
        case .abyss:
            colors = [Color.bioTeal, Color.bioCyan.opacity(0.8), Color.bioRose, Color.bioTeal]
        case .coral:
            colors = [Color.bioCoral, Color.bioAmber, Color.bioEmerald, Color.bioRose]
        }
        return colors[index % colors.count]
    }
}

// MARK: - PremiumGlassCard
//
// Единая стеклянная карточка для комнат, панелей, сообщений.
// • Ultra-thin material с сильным размытием
// • Стекло: полупрозрачный белый 4%
// • Тонкая неоновая обводка 0.5pt (cyan→emerald)
// • Мягкое внешнее свечение
struct PremiumGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    var glow: Bool = true
    var ringColor: LinearGradient = Color.bioNeonRing
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(
                ZStack {
                    // Стекло — полупрозрачный белый 4%
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(0.04))
                    // Верхний блик
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), .clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.3)
                            )
                        )
                }
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                // Тонкая неоновая рамка 0.5pt
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(ringColor, lineWidth: 0.5)
            )
            .shadow(
                color: glow ? Color.bioCyan.opacity(0.12) : .clear,
                radius: glow ? 14 : 0,
                x: 0, y: 4
            )
            .shadow(color: .black.opacity(0.5), radius: 14, x: 0, y: 4)
    }
}

// MARK: - BioluminescentButton
//
// Единая кнопка для ВСЕХ CTA (создать комнату, профиль, ссылки).
// • Glassmorphism + неоновая рамка 0.5pt
// • Мягкое внешнее свечение (растёт при нажатии)
// • Spring-анимация нажатия
struct BioluminescentButton: View {
    let action: () -> Void
    @ViewBuilder var label: () -> AnyView
    var glowColor: Color = .bioCyan
    var filled: Bool = false

    init(
        action: @escaping () -> Void,
        glowColor: Color = .bioCyan,
        filled: Bool = false,
        @ViewBuilder label: @escaping () -> AnyView
    ) {
        self.action = action
        self.glowColor = glowColor
        self.filled = filled
        self.label = label
    }

    @State private var pressed = false

    var body: some View {
        Button(action: {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        }) {
            label()
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(filled ? .white : .raveTextPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    ZStack {
                        if filled {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    LinearGradient(
                                        colors: [glowColor.opacity(0.85), glowColor.opacity(0.55)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        } else {
                            // Стекло — единый стиль
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.04))
                                .background(.ultraThinMaterial)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    // Неоновая рамка 0.5pt
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [glowColor.opacity(0.6), glowColor.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                // Внешнее свечение — растёт при нажатии
                .shadow(
                    color: glowColor.opacity(pressed ? 0.45 : 0.18),
                    radius: pressed ? 18 : 10,
                    x: 0, y: 0
                )
                .scaleEffect(pressed ? 0.97 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

// MARK: - Glow Pulse Modifier (для реакций чата / голоса)
struct GlowPulseModifier: ViewModifier {
    var color: Color = .bioCyan
    var minRadius: CGFloat = 4
    var maxRadius: CGFloat = 14
    var period: Double = 2.0
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.5), radius: pulse ? maxRadius : minRadius)
            .onAppear {
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

extension View {
    func glowPulse(
        color: Color = .bioCyan,
        minRadius: CGFloat = 4,
        maxRadius: CGFloat = 14,
        period: Double = 2.0
    ) -> some View {
        modifier(GlowPulseModifier(color: color, minRadius: minRadius, maxRadius: maxRadius, period: period))
    }

    func neonText(color: Color = .bioCyan, radius: CGFloat = 8) -> some View {
        self.shadow(color: color.opacity(0.8), radius: radius)
            .shadow(color: color.opacity(0.4), radius: radius * 2)
    }

    /// Премиальное матовое стекло (alias для PremiumGlassCard как модификатор).
    func premiumGlass(
        cornerRadius: CGFloat = 18,
        opacity: Double = 0.04,
        ringColor: LinearGradient = Color.bioNeonRing,
        glow: Bool = true
    ) -> some View {
        PremiumGlassCard(
            cornerRadius: cornerRadius,
            glow: glow,
            ringColor: ringColor
        ) { self }
    }
}
