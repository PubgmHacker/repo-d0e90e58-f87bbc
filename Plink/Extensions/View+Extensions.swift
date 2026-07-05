import SwiftUI

// MARK: - View Extensions

extension View {
    /// Shimmer loading placeholder
    func shimmer(_ active: Bool = true) -> some View {
        modifier(ShimmerModifier(active: active))
    }

    /// Скрывает клавиатуру при тапе по фону. Применять к ZStack-фону экрана.
    func dismissKeyboardOnTap() -> some View {
        modifier(DismissKeyboardOnTapModifier())
    }

    /// Стандартный модификатор для экранов с текстовыми полями:
    /// свайп вниз по скроллу + тап по фону скрывают клавиатуру.
    func interactiveKeyboardDismiss() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTap()
    }

    /// Card-style background
    func raveCardStyle() -> some View {
        self
            .padding()
            .background(Color.raveCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.raveSurface, lineWidth: 1)
            )
    }

    /// Primary button style
    func raveButtonStyle() -> some View {
        self
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.ravePrimary)
            .clipShape(Capsule())
    }

    /// Secondary button style
    func raveSecondaryButtonStyle() -> some View {
        self
            .font(.headline)
            .foregroundColor(.ravePrimary)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.raveCard)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.ravePrimary, lineWidth: 1.5)
            )
    }

    /// Conditionally apply modifier
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Shimmer Modifier
struct ShimmerModifier: ViewModifier {
    let active: Bool

    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        if active {
            content
                .redacted(reason: .placeholder)
                .overlay(
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.15), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.5 - geo.size.width * 0.25)
                    }
                    .clipped()
                )
                .onAppear {
                    withAnimation(
                        .linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                    ) {
                        phase = 1
                    }
                }
        } else {
            content
        }
    }
}

// MARK: - Shimmer Gradient Text Modifier
/// Переливающийся градиентный текст. Маска сдвигает видимость по горизонтали.
///
/// 🔧 POLISH: smoother animation — was `.linear(duration: 3.5)` with phase 0→2,
/// which created a visible "jump" at loop restart (gradient snapped back).
/// Now: phase goes -1 → 2 (longer travel), `.easeInOut(duration: 4.5)` for
/// smoother accel/decel, and the gradient is duplicated so the wrap-around
/// is seamless. Matches the smooth rotation of the avatar ring (4s period).
struct ShimmerGradientTextModifier: ViewModifier {
    let colors: [Color]
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                LinearGradient(
                    // 🔧 Duplicate the color stops so the gradient wraps smoothly
                    // when phase loops back to start. Without this, there's a visible
                    // jump because the gradient ends with color[N-1] but restarts at color[0].
                    colors: colors + colors,
                    startPoint: UnitPoint(x: phase, y: 0.5),
                    endPoint: UnitPoint(x: phase + 1, y: 0.5)
                )
            )
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 4.5)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 2
                }
            }
    }
}

extension View {
    /// Переливающийся градиентный текст с анимацией 3.5 сек (cyan→emerald спектр).
    func shimmerGradientText(colors: [Color] = [
        Color.bioCyan, Color.bioEmerald,
        Color.bioTeal, Color.bioCyan
    ]) -> some View {
        modifier(ShimmerGradientTextModifier(colors: colors))
    }
}

// MARK: - Animated Stroke Modifier (пульсирующая обводка)
/// Вращает AngularGradient вокруг центра контента — обводка пульсирует.
struct AnimatedStrokeModifier: ViewModifier {
    let colors: [Color]
    let lineWidth: CGFloat
    @State private var rotation: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: colors,
                            center: .center
                        ),
                        lineWidth: lineWidth
                    )
                    .rotationEffect(.degrees(rotation))
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 4)
                    .repeatForever(autoreverses: false)
                ) {
                    rotation = 360
                }
            }
    }
}

extension View {
    /// Пульсирующая обводка аватарки (cyan→emerald спектр, 4 сек цикл).
    func premiumStroke(lineWidth: CGFloat = 2.5) -> some View {
        modifier(AnimatedStrokeModifier(
            colors: [
                Color.bioCyan,
                Color.bioObsidian,
                Color.bioEmerald,
                Color.bioObsidian,
                Color.bioCyan,
            ],
            lineWidth: lineWidth
        ))
    }

    /// 🔧 NEW: Admin обводка аватарки — vivid scarlet red (was dull rose).
    /// 🔧 VIVID: user said «тусклая розовая». Replaced pink 0xFF8FA3 with
    /// bright 0xFFB800 gold accent for visible contrast against scarlet base.
    /// 4 сек цикл (matches avatar ring rotation period).
    func adminStroke(lineWidth: CGFloat = 2.5) -> some View {
        modifier(AnimatedStrokeModifier(
            colors: [
                Color.raveDanger,         // 0xFF1538 vivid scarlet
                Color(hex: 0xFFB800),     // warm gold (visible contrast point)
                Color.raveDanger,         // scarlet
                Color(hex: 0xFFFFFF),     // white highlight (peak brightness)
                Color.raveDanger,         // scarlet
            ],
            lineWidth: lineWidth
        ))
    }
}

// MARK: - Admin Shimmer Text Modifier (переливающийся красный для админов)
/// 🔧 Pack v3: Анимированный переливающийся градиент для ников админов в чате.
///
/// 🔧 FIX: was using `.overlay(LinearGradient.mask(content))` which layered
/// the gradient ON TOP of the white text → visible "double layer" conflict.
/// Now: `.foregroundStyle(LinearGradient)` replaces text color with gradient.
///
/// 🔧 VIVID: пользователь сказал «вяло переливается тускло». Причины были:
/// 1. Цвета 0xFF4D6D/0xFF8FA3/0xFF6B6B — rose/pink спектр, не сочный красный.
///    Заменил на 0xFF1538 (vivid scarlet) → 0xFFB800 (warm gold accent) →
///    0xFF1538 → яркий контраст красного с золотом, очень заметно.
/// 2. `.easeInOut(duration: 4.5)` — слишком медленно (4.5s).
///    Ускорил до 2.8s — заметное переливание, но не нервное.
/// 3. phase travel -1 → 2 (3x ширины) — длинный свип, хорошо видно движение.
struct AdminShimmerTextModifier: ViewModifier {
    let colors: [Color]
    @State private var phase: CGFloat = -1

    init(colors: [Color] = [
        Color(hex: 0xFF1538),   // vivid scarlet
        Color(hex: 0xFFB800),   // warm gold accent (creates visible "shimmer pass")
        Color(hex: 0xFF1538),   // scarlet again
        Color(hex: 0xFFFFFF),   // white highlight (peak brightness)
        Color(hex: 0xFF1538),   // scarlet
        Color(hex: 0xFFB800),   // gold
        Color(hex: 0xFF1538),   // scarlet (wraps to start)
    ]) {
        self.colors = colors
    }

    func body(content: Content) -> some View {
        content
            // 🔧 FIX: foregroundStyle REPLACES the text color with the gradient.
            .foregroundStyle(
                LinearGradient(
                    colors: colors,
                    startPoint: UnitPoint(x: phase, y: 0.5),
                    endPoint: UnitPoint(x: phase + 1, y: 0.5)
                )
            )
            // 🔧 SUBTLE GLOW: makes the shimmer visibly pop against dark background
            .shadow(color: Color(hex: 0xFF1538).opacity(0.6), radius: 3)
            .onAppear {
                withAnimation(
                    // 🔧 VIVID: faster 2.8s instead of 4.5s — visible shimmer pass
                    .easeInOut(duration: 2.8)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 2
                }
            }
    }
}

extension View {
    /// 🔧 Pack v3: Переливающийся красный текст для админов
    func adminShimmerText() -> some View {
        modifier(AdminShimmerTextModifier())
    }
}

// MARK: - Dismiss Keyboard On Tap Modifier
/// Скрывает клавиатуру при тапе по любой пустой области.
struct DismissKeyboardOnTapModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
            )
    }
}
