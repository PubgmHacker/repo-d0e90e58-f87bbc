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
        // 🔧 FIX: Canvas was being constrained to the top portion of the screen
        // inside NavigationStack + TabView. Adding .frame(maxWidth/maxHeight: .infinity)
        // forces the Group to fill ALL available space before .ignoresSafeArea() extends it.
        // Without this, the Canvas size parameter returns a small height and orbs only
        // render in the top 1/3 — user reported "background cuts off at top".
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
                Color.bioObsidian
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)  // 🔧 CRITICAL FIX
        .overlay(
            LinearGradient(
                colors: [.clear, Color.bioObsidian.opacity(dimming * 0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
        .overlay(
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

    /// 🔧 PACK v5: 9 биолюминесцентных облаков — равномерно по всему экрану
    /// (3 верх / 3 центр / 3 низ). Увеличены центральные и нижние орбы (380-500px)
    /// чтобы пробиваться сквозь `.ultraThinMaterial` карточки и tab bar.
    ///
    /// 🔧 DIVERSITY: добавлены warm accent цвета (amber/coral) для разнообразия —
    /// был только cyan/emerald спектр, теперь более живая палитра.
    ///
    /// 🔧 FIX: пользователь жаловался «в центре и снизу орбов нет». Причина:
    /// центральные/нижние орбы были 280-380px при opacity cap 0.95×energy —
    /// недостаточно, чтобы пробиться через `.ultraThinMaterial` карточек
    /// и opaque tab bar. Теперь: 380-500px, opacity cap 1.1 (с лёгким overflow).
    private func drawClouds(context: GraphicsContext, size: CGSize, time: Double) {
        let clouds: [(cx: Double, cy: Double, r: Double, speed: Double, phase: Double, colorIdx: Int)] = [
            // ─── Верхняя треть (3 облака) ───
            (0.15, 0.10, 360, 0.16, 0.0, 0),    // верх-лево — cyan
            (0.55, 0.06, 320, 0.20, 1.2, 2),    // верх-центр — amber (warm)
            (0.88, 0.16, 340, 0.24, 2.4, 1),    // верх-право — emerald
            // ─── Центральная треть (3 облака, КРУПНЕЕ) ───
            (0.20, 0.45, 480, 0.14, 3.6, 3),    // центр-лево — coral (warm accent)
            (0.55, 0.50, 460, 0.18, 4.8, 0),    // центр-центр — крупный cyan
            (0.82, 0.48, 440, 0.22, 6.0, 1),    // центр-право — emerald
            // ─── Нижняя треть (3 облака, КРУПНЕЕ + выше opacity) ───
            (0.15, 0.85, 460, 0.20, 7.2, 4),    // низ-лево — teal
            (0.50, 0.95, 500, 0.12, 8.4, 2),    // низ-центр — крупный amber (warm)
            (0.85, 0.82, 440, 0.26, 9.6, 0),    // низ-право — cyan
        ]

        for (_, cloud) in clouds.enumerated() {
            // 🔧 PACK v5: увеличенная амплитуда движения
            let dx = sin(time * cloud.speed + cloud.phase) * 140
            let dy = cos(time * cloud.speed * 0.7 + cloud.phase) * 100
            let cx = cloud.cx * size.width + dx
            let cy = cloud.cy * size.height + dy
            // 🔧 PACK v5: большая дельта радиуса
            let radius = cloud.r * (0.82 + 0.38 * sin(time * 0.5 + cloud.phase))

            let color = palette.color(for: cloud.colorIdx)
            // 🔧 PACK v5: более высокий pulse-диапазон
            let pulse = 0.65 + 0.40 * sin(time * 0.6 + cloud.phase)
            // 🔧 PACK v5: opacity cap поднят до 1.1 (с лёгким overflow для яркости)
            // Центральные и нижние орбы — ещё ярче (компенсация перекрытий)
            let locationBoost = cloud.cy > 0.4 ? 1.15 : 1.0
            let opacity = min(pulse * energy * 1.1 * locationBoost, 1.0)

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
//
// 🔧 IMPROVED: теперь пульсирует не только radius, но и opacity тени —
// иначе свечение выглядело статичным. Добавлены minOpacity/maxOpacity
// для тонкой настройки интенсивности (по умолчанию 0.15↔0.45 — сдержанно).
struct GlowPulseModifier: ViewModifier {
    var color: Color = .bioCyan
    var minRadius: CGFloat = 4
    var maxRadius: CGFloat = 14
    var minOpacity: Double = 0.15
    var maxOpacity: Double = 0.45
    var period: Double = 2.0
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: color.opacity(pulse ? maxOpacity : minOpacity),
                radius: pulse ? maxRadius : minRadius
            )
            .onAppear {
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Breathing Scale Modifier
//
// 🔧 NEW: Тонкое «дыхание» — пульсирующее масштабирование элемента.
// Используется для логотипов, аватаров, точек онлайна — где свечение тени
// неуместно, но хочется лёгкого ощущения «живости». По умолчанию 1.00↔1.04
// с периодом 2.6с — спокойно и ненавязчиво.
struct BreathingScaleModifier: ViewModifier {
    var minScale: CGFloat = 1.0
    var maxScale: CGFloat = 1.04
    var period: Double = 2.6
    @State private var breathe = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(breathe ? maxScale : minScale)
            .onAppear {
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            }
    }
}

// 🔧 NEW: Условное дыхание — анимация запускается только если isActive == true.
// Используется для online-точек друзей (только онлайн-друзья пульсируют),
// индикаторов LIVE и т.п. — чтобы не анимировать статичные/офлайн элементы.
struct ConditionalBreathing: ViewModifier {
    var isActive: Bool
    var minScale: CGFloat = 1.0
    var maxScale: CGFloat = 1.25
    var minOpacity: Double = 0.55
    var maxOpacity: Double = 1.0
    var period: Double = 2.0
    @State private var breathe = false

    func body(content: Content) -> some View {
        if isActive {
            content
                .scaleEffect(breathe ? maxScale : minScale)
                .opacity(breathe ? maxOpacity : minOpacity)
                .onAppear {
                    withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                        breathe = true
                    }
                }
        } else {
            content
        }
    }
}

// 🔧 NEW: Условное свечение тени — пульсирует только если isActive == true.
// Используется для CTA-кнопок: glow появляется когда форма валидна (canProceed),
// и пропадает когда кнопка disabled. В отличие от простого glowPulse, даёт
// функциональный feedback вместо декоративного.
struct ConditionalGlow: ViewModifier {
    var isActive: Bool
    var color: Color = .bioCyan
    var minRadius: CGFloat = 6
    var maxRadius: CGFloat = 14
    var minOpacity: Double = 0.15
    var maxOpacity: Double = 0.35
    var period: Double = 2.0
    @State private var pulse = false

    func body(content: Content) -> some View {
        if isActive {
            content
                .shadow(
                    color: color.opacity(pulse ? maxOpacity : minOpacity),
                    radius: pulse ? maxRadius : minRadius
                )
                .onAppear {
                    withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    func glowPulse(
        color: Color = .bioCyan,
        minRadius: CGFloat = 4,
        maxRadius: CGFloat = 14,
        minOpacity: Double = 0.15,
        maxOpacity: Double = 0.45,
        period: Double = 2.0
    ) -> some View {
        modifier(
            GlowPulseModifier(
                color: color,
                minRadius: minRadius,
                maxRadius: maxRadius,
                minOpacity: minOpacity,
                maxOpacity: maxOpacity,
                period: period
            )
        )
    }

    /// 🔧 NEW: Тонкое масштабирование-дыхание для логотипов/аватаров/точек.
    func breathingScale(
        minScale: CGFloat = 1.0,
        maxScale: CGFloat = 1.04,
        period: Double = 2.6
    ) -> some View {
        modifier(
            BreathingScaleModifier(
                minScale: minScale,
                maxScale: maxScale,
                period: period
            )
        )
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
