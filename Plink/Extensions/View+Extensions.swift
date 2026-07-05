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
//
// 🔧 VISIBLE ROTATION: пользователь жаловался «не заметно что анимированная и
// вращается». Причины:
// 1. Все цвета в градиенте были слишком похожи (все красные) — вращение
//    AngularGradient не давало видимого контраста.
// 2. linear(duration: 4) — слишком медленно для rotation, глаз не замечает.
// 3. Не было glow — обводка сливалась с фоном.
// Fix: добавлен bright accent (0xFF4D4D light red) как явная «отметка» в
// градиенте, rotation ускорен до 3с, добавлен shadow glow.
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
                    // 🔧 GLOW: делает обводку видимой на тёмном фоне
                    .shadow(color: colors.first?.opacity(0.6) ?? .clear, radius: 4)
            )
            .onAppear {
                withAnimation(
                    // 🔧 VISIBLE: 3с rotation — заметно, но не нервно (было 4с)
                    .linear(duration: 3)
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

    /// 🔧 Admin обводка аватарки — база алый, переливание тёмными оттенками.
    /// 🔧 VISIBLE: добавлен bright accent (0xFF4D4D) как явная «отметка» в
    /// градиенте, чтобы было видно вращение. lineWidth 3 (было 2.5) — заметнее.
    /// Синхронизирована с ником — та же палитра, та же логика.
    func adminStroke(lineWidth: CGFloat = 3) -> some View {
        modifier(AnimatedStrokeModifier(
            colors: [
                Color(hex: 0xFF1538),   // scarlet — база
                Color(hex: 0xCC0000),   // crimson — затемнение
                Color(hex: 0xFF4D4D),   // 🔧 BRIGHT ACCENT — явная «отметка» для видимости вращения
                Color(hex: 0xB00000),   // dark crimson — пик тёмной волны
                Color(hex: 0xFF4D4D),   // bright accent (другая сторона)
                Color(hex: 0xCC0000),   // crimson
                Color(hex: 0xFF1538),   // scarlet — обратно в базу (loop)
            ],
            lineWidth: lineWidth
        ))
    }
}

// MARK: - Admin Shimmer Text Modifier (переливающийся КРАСНЫЙ для админов)
//
// 🔧 USER REQUEST v3: «переливание медленнее + многослойное, сейчас из алого
// сразу в тёмный».
//
// 🔧 MULTILAYERED: 11 стопов вместо 7 — больше промежуточных оттенков между
// алым и тёмно-красным. Создаёт плавную волну без резких скачков.
//
// 🔧 SLOWER: 4с вместо 2.8с — заметное, но спокойное переливание.
//
// 🔧 PALETTE: база алый, тёмная волна проходит плавно через 11 оттенков:
// scarlet → red → crimson → dark-red → crimson → red → scarlet → red →
// crimson → dark-red → scarlet (двойная волна за один цикл — больше «слоёв»)
struct AdminShimmerTextModifier: ViewModifier {
    let colors: [Color]
    @State private var phase: CGFloat = -1

    init(colors: [Color] = [
        Color(hex: 0xFF1538),   // 1. scarlet — база
        Color(hex: 0xF01020),   // 2. bright scarlet (чуть темнее)
        Color(hex: 0xE60012),   // 3. pure red
        Color(hex: 0xD80010),   // 4. deep red
        Color(hex: 0xCC0000),   // 5. crimson
        Color(hex: 0xD80010),   // 6. deep red (подъём)
        Color(hex: 0xE60012),   // 7. pure red
        Color(hex: 0xF01020),   // 8. bright scarlet
        Color(hex: 0xCC0000),   // 9. crimson (вторая волна — многослойность)
        Color(hex: 0xD80010),   // 10. deep red
        Color(hex: 0xFF1538),   // 11. scarlet — обратно в базу (бесшовный loop)
    ]) {
        self.colors = colors
    }

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                LinearGradient(
                    colors: colors,
                    startPoint: UnitPoint(x: phase, y: 0.5),
                    endPoint: UnitPoint(x: phase + 1, y: 0.5)
                )
            )
            // 🔧 GLOW: red shadow makes the shimmer visibly "pop"
            .shadow(color: Color(hex: 0xFF1538).opacity(0.7), radius: 4)
            .shadow(color: Color(hex: 0xFF4D4D).opacity(0.4), radius: 8)
            .onAppear {
                withAnimation(
                    // 🔧 SLOWER: 4с — заметное, но спокойное переливание
                    .easeInOut(duration: 4.0)
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
