// Plink/Design/Cinematic/PremiumComponents.swift
//
// Premium UI components — shimmer text, username styles, badges.
// Restored from old CinemaComponents.swift + SettingsSlidePanel.swift.

import SwiftUI

// MARK: - Premium Username Text

struct PremiumUsernameText: View {
    let text: String
    let isPremium: Bool
    var isAdmin: Bool = false
    var font: Font = .system(size: 18, weight: .bold)

    var body: some View {
        if isAdmin {
            Text(text)
                .font(font)
                .adminShimmerText()
        } else if isPremium {
            Text(text)
                .font(font)
                .shimmerGradientText(colors: premiumColors)
        } else {
            Text(text)
                .font(font)
                .foregroundColor(Cinema2026.text)
        }
    }

    private let premiumColors: [Color] = [
        Cinema2026.accent,
        Cinema2026.accent,
        Cinema2026.accent,
        Cinema2026.accent,
    ]
}

// MARK: - Admin Badge Chip

struct AdminBadgeChip: View {
    var body: some View {
        Text("АДМИН")
            .font(.system(size: 9, weight: .heavy))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Cinema2026.danger.opacity(0.2), in: Capsule())
            .foregroundStyle(Cinema2026.danger)
    }
}

// MARK: - Text Extensions

extension Text {
    func adminShimmerText() -> some View {
        self.foregroundStyle(Cinema2026.amber)
            .shadow(color: Cinema2026.amber.opacity(0.4), radius: 4)
    }
}

// MARK: - View Extensions

extension View {
    func shimmerGradientText(colors: [Color] = [Cinema2026.accent, Cinema2026.amber]) -> some View {
        self.foregroundStyle(
            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
        )
        .shadow(color: colors.first?.opacity(0.4) ?? .clear, radius: 4)
    }

    @ViewBuilder func ifTransform<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }

    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
        }
    }
}

// MARK: - Pulsing Dot

struct PulsingDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(pulse ? 1.3 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Live Badge

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
