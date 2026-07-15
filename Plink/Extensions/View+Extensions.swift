import SwiftUI

// MARK: - View Extensions

extension View {
    /// Shimmer loading placeholder
    func shimmer(_ active: Bool = true) -> some View {
        modifier(ShimmerModifier(active: active))
    }

    /// dismissKeyboardOnTap() is defined in PremiumComponents.swift
    /// (using UIApplication.shared.sendAction instead of custom modifier)

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

// shimmerGradientText(colors:) is defined in PremiumComponents.swift
// (using LinearGradient foregroundStyle instead of custom modifier)

// MARK: - Animated Stroke Modifier (пульсирующая обводка)
/// Вращает AngularGradient вокруг центра контента — обводка пульсирует.
//
// 🔧 VISIBLE ROTATION v2: пользователь жаловался «обводка не переливается,
// выглядит статично». Применил тот же подход что к админ-нику — многослойные
// тени для яркости + более яркие accent-цвета в градиенте.
//
// 🔧 LAYERS:
// 1. Inner stroke (AngularGradient) — вращается, lineWidth 3
// 2. Outer glow shadow (scarlet 0.8 opacity, radius 6) — пульсирует яркостью
// 3. Bright pulse shadow (light red 0.6, radius 12) — добавляет «halo» эффект
//
// 🔧 COLORS: bright accent 0xFF4D4D на 3 позициях в градиенте (was 2) —
// более частая «отметка» = заметнее вращение.
struct AnimatedStrokeModifier: ViewModifier {
    let colors: [Color]
    let lineWidth: CGFloat
    @State private var rotation: Double = 0
    @State private var pulse: Bool = false  // 🔧 NEW: brightness pulse state

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
                    // 🔧 MULTI-LAYER GLOW: 3 shadows разной интенсивности
                    // — тот же подход что у админ-ника, делает обводку «живой»
                    .shadow(color: colors.first?.opacity(0.8) ?? .clear, radius: 6)  // tight glow
                    .shadow(color: Color(hex: 0xFF4D4D).opacity(pulse ? 0.7 : 0.3), radius: 12)  // 🔧 PULSING halo
                    .shadow(color: Color(hex: 0xFF1538).opacity(pulse ? 0.5 : 0.2), radius: 18)  // 🔧 PULSING outer halo
            )
            .onAppear {
                // 🔧 ROTATION: 3с — заметное вращение
                withAnimation(
                    .linear(duration: 3)
                    .repeatForever(autoreverses: false)
                ) {
                    rotation = 360
                }
                // 🔧 PULSE: 2с — пульсация яркости halo (десинхронизирована с rotation
                // для более «живого» эффекта)
                withAnimation(
                    .easeInOut(duration: 2.0)
                    .repeatForever(autoreverses: true)
                ) {
                    pulse = true
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
    /// 🔧 VISIBLE v2: 3 bright accent (0xFF4D4D) в градиенте (было 2) — более
    /// частая «отметка» = заметнее вращение. + многослойные тени в AnimatedStrokeModifier.
    func adminStroke(lineWidth: CGFloat = 3) -> some View {
        modifier(AnimatedStrokeModifier(
            colors: [
                Color(hex: 0xFF1538),   // scarlet — база
                Color(hex: 0xFF4D4D),   // 🔧 BRIGHT ACCENT #1
                Color(hex: 0xCC0000),   // crimson — затемнение
                Color(hex: 0xB00000),   // dark crimson — пик тёмной волны
                Color(hex: 0xFF4D4D),   // 🔧 BRIGHT ACCENT #2
                Color(hex: 0xCC0000),   // crimson
                Color(hex: 0xFF4D4D),   // 🔧 BRIGHT ACCENT #3 (was 2 accents, now 3)
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
            // 🔧 TEXT STROKE: тонкая чёрная обводка через 4-directional shadow.
            // Без неё красный «испепеляет» буквы — они сливаются в пятно.
            // 4 shadow (up/down/left/right) по 0.5px каждая = эффект stroke.
            .shadow(color: .black.opacity(0.6), radius: 0.5, x: 0.5, y: 0)
            .shadow(color: .black.opacity(0.6), radius: 0.5, x: -0.5, y: 0)
            .shadow(color: .black.opacity(0.6), radius: 0.5, x: 0, y: 0.5)
            .shadow(color: .black.opacity(0.6), radius: 0.5, x: 0, y: -0.5)
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
