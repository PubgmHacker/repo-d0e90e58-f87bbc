// Plink/Extensions/View+MissingModifiers.swift
//
// GPT-5.6 SOL fix: recreate missing modifiers/styles that were in deleted files.
// ConditionalBreathing, GlassButtonStyle, RaveTextFieldStyle.

import SwiftUI

// MARK: - ConditionalBreathing
//
// Breathing animation modifier — scales view in a gentle pulse when isActive.
// Used by FriendsView for online indicator.

struct ConditionalBreathing: ViewModifier {
    let isActive: Bool
    let maxScale: CGFloat
    let period: Double

    @State private var breathing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive && breathing ? maxScale : 1.0)
            .onAppear {
                guard isActive else { return }
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}

// MARK: - GlassButtonStyle
//
// GPT-5.6 SOL: GlassButtonStyle is iOS 26+ only. Recreated as custom style
// with frosted glass appearance for iOS 17+ compatibility.

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Cinema2026.text)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - RaveTextFieldStyle
//
// Custom text field style with Cinema2026 palette.

struct RaveTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 16))
            .foregroundStyle(Cinema2026.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Cinema2026.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Cinema2026.divider, lineWidth: 0.5)
            )
    }
}
