// Plink/DesignSystem/V4Components.swift — GPT-5.6 V4 Secondary Screens
// Shared V4 components for secondary screens + button styles + helpers

import SwiftUI

// MARK: - V4SecondaryScreen (shared shell for sheet/push screens)

struct V4SecondaryScreen<Content: View>: View {
    let surface: PlinkLivingBackground.Surface
    let title: String
    let dismiss: () -> Void
    @Environment(PlinkThemeStore.self) private var themeStore
    @ViewBuilder let content: Content

    var body: some View {
        V4Surface(theme: themeStore.appTheme, surface: surface) {
            VStack(spacing: 0) {
                HStack {
                    Button(action: dismiss) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Cinema2026.text)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Cinema2026.text)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                content
            }
        }
    }
}

// MARK: - V4 Screen Header

struct V4ScreenHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Cinema2026.accent)
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Cinema2026.text)
        }
        .padding(.top, 8)
    }
}

// MARK: - V4 Button Styles

struct V4PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Cinema2026.background)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Cinema2026.accent, in: RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct V4SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Cinema2026.text)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Cinema2026.divider, lineWidth: 0.5))
    }
}

struct V4CircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Cinema2026.text)
            .frame(width: 44, height: 44)
            .background(Color.white.opacity(0.08), in: Circle())
    }
}

// MARK: - V4 Input Style

extension View {
    func v4InputStyle() -> some View {
        self
            .font(.system(size: 16))
            .foregroundStyle(Cinema2026.text)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Cinema2026.divider, lineWidth: 0.5))
    }
}

// MARK: - V4 Search Field

struct V4SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Cinema2026.secondary)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Cinema2026.secondary)
                }
            }
        }
        .v4InputStyle()
    }
}

// MARK: - V4 Empty / Error States

struct V4EmptyState: View {
    let title: String
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Cinema2026.secondary)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Cinema2026.text)
            if let action { Button("Повторить", action: action).buttonStyle(V4SecondaryButtonStyle()) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

struct V4ErrorState: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Cinema2026.amber)
            Text("Ошибка загрузки")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Cinema2026.text)
            Button("Повторить", action: retry)
                .buttonStyle(V4SecondaryButtonStyle())
                .frame(width: 200)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Settings Section + Row

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Cinema2026.secondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                content
            }
            .background(Cinema2026.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    var value: String? = nil
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(role == .destructive ? Cinema2026.danger : Cinema2026.accent)
                    .frame(width: 28)
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(role == .destructive ? Cinema2026.danger : Cinema2026.text)
                Spacer()
                if let value {
                    Text(value)
                        .font(.system(size: 14))
                        .foregroundStyle(Cinema2026.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Cinema2026.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme Switcher (for Profile/Home)

struct ThemeSwitcherSheet: View {
    @Environment(PlinkThemeStore.self) private var themeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        V4Surface(theme: themeStore.appTheme, surface: .profile) {
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Cinema2026.text).frame(width: 44, height: 44)
                    }
                    Spacer()
                    Text("Оформление").font(.system(size: 17, weight: .semibold)).foregroundStyle(Cinema2026.text)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)

                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(PlinkThemeCatalog.all) { theme in
                            ThemeOptionRow(theme: theme, isSelected: theme.id == themeStore.appTheme.id) {
                                try? themeStore.selectAppTheme(id: theme.id, hasPremium: PremiumStatusManager.shared.isPremium)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
}

private struct ThemeOptionRow: View {
    let theme: PlinkLivingTheme
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    LinearGradient(colors: theme.colors.map { $0.color }, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    if theme.access == .premium {
                        Image(systemName: "crown.fill").font(.system(size: 14)).foregroundStyle(Cinema2026.amber).padding(4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Cinema2026.text)
                    Text(theme.access == .free ? "Бесплатно" : "Plink+").font(.system(size: 12)).foregroundStyle(Cinema2026.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Cinema2026.accent)
                }
            }
            .padding(16)
            .background(Cinema2026.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isSelected ? Cinema2026.accent.opacity(0.4) : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PulsingDot (used by FriendsView)
struct PulsingDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(pulse ? 1.3 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

// MARK: - LiveBadge (used by TrendingCardView)
struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            PulsingDot(color: .white)
            Text("LIVE")
                .font(.system(size: 9, weight: .black))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Cinema2026.danger, in: Capsule())
        .foregroundStyle(.white)
    }
}

// MARK: - View.if modifier (used by SettingsSlidePanel)
extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - adminShimmerText (used by SettingsSlidePanel)
extension Text {
    func adminShimmerText() -> some View {
        self.foregroundStyle(Cinema2026.amber)
            .shadow(color: Cinema2026.amber.opacity(0.4), radius: 4)
    }
}

// MARK: - PosterImage (used by CompactRoomRail)
struct PosterImage: View {
    let url: String?

    var body: some View {
        AsyncImage(url: URL(string: url ?? "")) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(Cinema2026.surface)
        }
    }
}

// MARK: - adminStroke + premiumStroke (used by AvatarView's RingModifier)
extension View {
    func adminStroke(lineWidth: CGFloat = 2) -> some View {
        self.overlay(Circle().stroke(Cinema2026.amber, lineWidth: lineWidth))
    }

    func premiumStroke(lineWidth: CGFloat = 2) -> some View {
        self.overlay(Circle().stroke(Cinema2026.accent, lineWidth: lineWidth))
    }
}

// MARK: - shimmerGradientText (used by SettingsSlidePanel)
extension View {
    func shimmerGradientText(colors: [Color] = [Cinema2026.accent, Cinema2026.amber]) -> some View {
        self.foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            .shadow(color: colors.first?.opacity(0.4) ?? .clear, radius: 4)
    }
}

// MARK: - dismissKeyboardOnTap (used by ProfileView)
extension View {
    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}
