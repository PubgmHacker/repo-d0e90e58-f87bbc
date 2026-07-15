// Plink/Extensions/View+Glass.swift
//
// Glassmorphism modifier + PremiumButtonStyle
// Restored from Phase 9 cleanup — needed by PaywallView, ProfileView,
// AdminPanelView, SettingsSlidePanel and 5+ other views.

import SwiftUI

// MARK: - Glass Card Modifier

extension View {
    /// Telegram-style glassmorphism: blur + semi-transparent bg + border.
    /// Used across all Plink screens for cards, modals, toolbars.
    func glassCard(cornerRadius: CGFloat = 16, opacity: Double = 0.08) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(opacity))
                    .blur(radius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
    }

    /// Alias for backward compatibility (some views use telegramGlass).
    func telegramGlass(cornerRadius: CGFloat = 14, borderColor: Color = .clear) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor.opacity(0.2), lineWidth: 0.5)
            )
    }
}

// MARK: - Premium Button Style

struct PremiumButtonStyle: ButtonStyle {
    var filled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(filled ? Color(hex: 0x0E1113) : Color(hex: 0x2DE2E6))
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if filled {
                        LinearGradient(
                            colors: [Color(hex: 0x2DE2E6), Color(hex: 0x26D9A4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        Color.white.opacity(0.04)
                    }
                }
                .clipShape(Capsule())
                .opacity(configuration.isPressed ? 0.7 : 1.0)
            )
            .overlay(
                Capsule()
                    .strokeBorder(filled ? Color.clear : Color(hex: 0x2DE2E6).opacity(0.4), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// Note: Color(hex:alpha:) is already defined in Plink/Extensions/Color+Theme.swift
// Do not redeclare here — would cause 'Invalid redeclaration' + 'Ambiguous use'

// MARK: - Rave TextField Style

struct RaveTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(Cinema2026.text)
    }
}
