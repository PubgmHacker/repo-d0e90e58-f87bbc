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
struct ShimmerGradientTextModifier: ViewModifier {
    let colors: [Color]
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                LinearGradient(
                    colors: colors,
                    startPoint: UnitPoint(x: phase - 1, y: 0.5),
                    endPoint: UnitPoint(x: phase, y: 0.5)
                )
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 3.5)
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

    /// 🔧 NEW: Admin обводка аватарки (crimson→red спектр, 4 сек цикл).
    /// Используется для пользователей с role .admin или .founder.
    func adminStroke(lineWidth: CGFloat = 2.5) -> some View {
        modifier(AnimatedStrokeModifier(
            colors: [
                Color.raveDanger,
                Color.bioObsidian,
                Color(hex: 0xFF8FA3),
                Color.bioObsidian,
                Color.raveDanger,
            ],
            lineWidth: lineWidth
        ))
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
