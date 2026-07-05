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

    /// 🔧 PACK v6: УМЕНЬШЕНО до 5 орбов (было 9 — пользователь сказал «перегруз,
    /// слишком много налегающих друг на друга»). Замедлены все анимации.
    ///
    /// 🔧 SLOWER: speed уменьшен в ~2 раза, amplitude движения уменьшена
    /// (было 140×100 — слишком быстро «плыли», стало 80×60 — спокойно дрейфуют).
    ///
    /// 🔧 LAYOUT: 2 верх / 1 центр / 2 низ — равномерно, без перекрытий.
    /// Каждый орб имеет свой цвет (cyan/emerald/amber/teal/coral) — diversity.
    private func drawClouds(context: GraphicsContext, size: CGSize, time: Double) {
        let clouds: [(cx: Double, cy: Double, r: Double, speed: Double, phase: Double, colorIdx: Int)] = [
            // ─── Верх (2 облака) ───
            (0.20, 0.12, 380, 0.08, 0.0, 0),    // верх-лево — cyan
            (0.80, 0.10, 360, 0.10, 1.5, 2),    // верх-право — amber (warm)
            // ─── Центр (1 крупное облако) ───
            (0.50, 0.50, 520, 0.06, 3.0, 1),    // центр — крупный emerald
            // ─── Низ (2 облака) ───
            (0.22, 0.88, 400, 0.09, 4.5, 3),    // низ-лево — coral (warm)
            (0.78, 0.85, 380, 0.11, 6.0, 4),    // низ-право — teal
        ]

        for (_, cloud) in clouds.enumerated() {
            // 🔧 SLOWER: уменьшенная амплитуда — спокойный дрейф
            let dx = sin(time * cloud.speed + cloud.phase) * 80
            let dy = cos(time * cloud.speed * 0.7 + cloud.phase) * 60
            let cx = cloud.cx * size.width + dx
            let cy = cloud.cy * size.height + dy
            // 🔧 SLOWER: меньшая дельта радиуса — «дыхание» спокойнее
            let radius = cloud.r * (0.92 + 0.16 * sin(time * 0.25 + cloud.phase))

            let color = palette.color(for: cloud.colorIdx)
            // 🔧 SLOWER: pulse тоже замедлен (0.3 вместо 0.6)
            let pulse = 0.7 + 0.25 * sin(time * 0.3 + cloud.phase)
            let locationBoost = cloud.cy > 0.4 ? 1.15 : 1.0
            let opacity = min(pulse * energy * 1.05 * locationBoost, 1.0)

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

// MARK: - Settings Background (grayscale gradient, no orbs)
//
// 🔧 USER REQUEST: 'не с орбами а с чем то другим, сверху доминирует черный
// а ближе к центру серый уже и переливается (живой фон)'.
//
// 🔧 DESIGN: вертикальный градиент black (top) → grey (center) → black (bottom),
// с лёгкой горизонтальной переливающейся волной. Никаких орбов — чистая
// минималистичная серая палитра для B&W настроек.
struct SettingsBackground: View {
    var energy: Double = 0.5
    @State private var isInBackground = false
    @State private var phase: CGFloat = -1

    var body: some View {
        Group {
            if !isInBackground {
                TimelineView(.animation(minimumInterval: 1.0/30.0)) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        drawGradient(context: context, size: size, time: t)
                    }
                }
            } else {
                Color.bioObsidian
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            isInBackground = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            isInBackground = false
        }
    }

    /// 🔧 Vertical gradient + horizontal shimmer wave.
    /// Top: pure black (bioObsidian). Center: animated grey. Bottom: black.
    /// A subtle horizontal light band sweeps up-down slowly = "переливается".
    private func drawGradient(context: GraphicsContext, size: CGSize, time: Double) {
        // ── Base vertical gradient: black → grey → black ──
        let baseRect = CGRect(origin: .zero, size: size)
        let baseGradient = Gradient(colors: [
            Color(white: 0.04),   // near-black top
            Color(white: 0.18),   // dark grey upper-mid
            Color(white: 0.28),   // mid grey center
            Color(white: 0.18),   // dark grey lower-mid
            Color(white: 0.04),   // near-black bottom
        ])
        context.fill(
            Path(baseRect),
            with: .linearGradient(
                baseGradient,
                startPoint: .init(x: 0, y: 0),
                endPoint: .init(x: 0, y: size.height)
            )
        )

        // ── Horizontal shimmer band (slow sweep) ──
        // A soft horizontal light band that travels vertically — gives "живой" feel.
        let bandY = size.height * (0.5 + 0.35 * sin(time * 0.15))
        let bandHeight = size.height * 0.4
        let bandOpacity = 0.06 * energy
        let bandRect = CGRect(
            x: 0,
            y: bandY - bandHeight / 2,
            width: size.width,
            height: bandHeight
        )
        context.fill(
            Path(bandRect),
            with: .linearGradient(
                Gradient(colors: [
                    Color.white.opacity(0),
                    Color.white.opacity(bandOpacity),
                    Color.white.opacity(0),
                ]),
                startPoint: .init(x: 0, y: bandRect.minY),
                endPoint: .init(x: 0, y: bandRect.maxY)
            )
        )

        // ── Subtle diagonal sheen (very faint) ──
        // Adds premium metallic feel — like brushed aluminum.
        let sheenOffset = sin(time * 0.1) * size.width * 0.3
        let sheenRect = CGRect(
            x: sheenOffset - size.width * 0.5,
            y: 0,
            width: size.width * 0.4,
            height: size.height
        )
        context.fill(
            Path(sheenRect),
            with: .linearGradient(
                Gradient(colors: [
                    Color.white.opacity(0),
                    Color.white.opacity(0.03 * energy),
                    Color.white.opacity(0),
                ]),
                startPoint: .init(x: sheenRect.minX, y: 0),
                endPoint: .init(x: sheenRect.maxX, y: 0)
            )
        )
    }
}

// MARK: - Bio Palette
//
// 🔧 PER-TAB PALETTES: каждая вкладка имеет свой уникальный фон.
// .ocean — Home (cyan/emerald/amber/teal/coral — текущий)
// .crimson — Rooms (тёплые красные/оранжевые — отличает от Home)
// .amber — AI (тёплые янтарные/коралл — премиум-чувство)
// .emerald — Friends (зелёные/изумрудные — социальное тепло)
// .mono — Settings (чёрно-белая палитра с лёгким blue accent)
enum BioPalette {
    case ocean       // Home
    case abyss
    case coral
    case crimson     // Rooms
    case amber       // AI
    case emerald     // Friends
    case mono        // Settings (B&W)

    func color(for index: Int) -> Color {
        let colors: [Color]
        switch self {
        case .ocean:
            colors = [Color.bioCyan, Color.bioEmerald, Color.bioAmber, Color.bioTeal, Color.bioCoral]
        case .abyss:
            colors = [Color.bioTeal, Color.bioCyan.opacity(0.8), Color.bioRose, Color.bioTeal]
        case .coral:
            colors = [Color.bioCoral, Color.bioAmber, Color.bioEmerald, Color.bioRose]
        case .crimson:
            // 🔧 ROOMS: тёплая палитра — красный/оранжевый/розовый спектр
            colors = [
                Color(hex: 0xFF6B35),   // vivid orange
                Color(hex: 0xFF1538),   // scarlet red
                Color(hex: 0xFFB800),   // amber
                Color(hex: 0xE63946),   // coral red
                Color(hex: 0xFF8C42),   // warm orange
            ]
        case .amber:
            // 🔧 AI: янтарная премиум-палитра
            colors = [
                Color.bioAmber,         // 0xFFB454
                Color.bioCoral,         // 0xFF7B54
                Color(hex: 0xFFD700),   // gold
                Color(hex: 0xFF8C00),   // dark orange
                Color(hex: 0xE6A800),   // deep amber
            ]
        case .emerald:
            // 🔧 FRIENDS: зелёная палитра — социальное тепло
            colors = [
                Color.bioEmerald,       // 0x34D399
                Color.bioTeal,          // 0x14B8A6
                Color(hex: 0x10B981),   // emerald
                Color(hex: 0x059669),   // dark emerald
                Color(hex: 0x6EE7B7),   // light emerald
            ]
        case .mono:
            // 🔧 SETTINGS: чёрно-белая палитра с лёгким steel accent
            colors = [
                Color(white: 0.85),    // light grey
                Color(white: 0.55),    // mid grey
                Color(white: 0.95),    // near white
                Color(hex: 0x4A5568),  // steel blue-grey
                Color(white: 0.65),    // silver
            ]
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

    /// 🔧 TELEGRAM-STYLE: прозрачное жидкое стекло + тонкая металлическая обводка.
    /// Используется для ВСЕХ кнопок в приложении — единый стиль как у Telegram.
    /// Особенности:
    /// - .ultraThinMaterial (жидкое стекло)
    /// - Чёрная полупрозрачная обводка 0.5pt (metalllic look)
    /// - Лёгкая внутренняя тень сверху (имитация блика стекла)
    /// - Без заливки цветом — полностью прозрачный
    /// - cornerRadius 14 (как у Telegram-кнопок)
    func telegramGlass(
        cornerRadius: CGFloat = 14,
        borderColor: Color = .black.opacity(0.4)
    ) -> some View {
        self
            .background(
                ZStack {
                    // Жидкое стекло
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                    // Верхний блик (glass highlight)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.4)
                            )
                        )
                }
            )
            .overlay(
                // Металлическая обводка
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    /// 🔧 TEXT STROKE: тонкая чёрная обводка для букв/текста через 4-directional shadow.
    /// Используется для лейблов в Settings/Profile (Аккаунт Плинк, email, ID) —
    /// улучшает читаемость на живом фоне. Без обводки текст «сливается» с фоном.
    /// SwiftUI не имеет native text stroke — это workaround через 4 тени.
    func textStroke(opacity: Double = 0.5, radius: CGFloat = 0.4) -> some View {
        self
            .shadow(color: .black.opacity(opacity), radius: radius, x: radius, y: 0)
            .shadow(color: .black.opacity(opacity), radius: radius, x: -radius, y: 0)
            .shadow(color: .black.opacity(opacity), radius: radius, x: 0, y: radius)
            .shadow(color: .black.opacity(opacity), radius: radius, x: 0, y: -radius)
    }
}
