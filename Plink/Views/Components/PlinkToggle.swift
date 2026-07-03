import SwiftUI

// MARK: - PlinkToggle
/// 🔧 PREMIUM TOGGLE: Custom toggle styled like iOS Settings / Telegram.
/// Replaces the default iOS Toggle which has visual gaps and a generic look.
/// Features:
///   • Pill-shaped track with smooth fill animation
///   • White knob with shadow
///   • Cyan/emerald gradient when ON (matches Bioluminescent palette)
///   • Haptic feedback on toggle
///   • Spring animation
struct PlinkToggle: View {
    @Binding var isOn: Bool
    var enabled: Bool = true

    private let trackWidth: CGFloat = 51
    private let trackHeight: CGFloat = 31
    private let knobSize: CGFloat = 27
    private let knobPadding: CGFloat = 2

    var body: some View {
        Button {
            guard enabled else { return }
            HapticManager.impact(.light)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isOn.toggle()
            }
        } label: {
            ZStack {
                // Track
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(
                        LinearGradient(
                            colors: isOn
                                ? [Color.bioCyan, Color.bioEmerald]
                                : [Color.white.opacity(0.1), Color.white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: trackWidth, height: trackHeight)
                    .overlay(
                        // Subtle inner shadow when OFF for depth
                        RoundedRectangle(cornerRadius: trackHeight / 2)
                            .strokeBorder(
                                Color.white.opacity(isOn ? 0 : 0.08),
                                lineWidth: 0.5
                            )
                    )

                // Knob
                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .offset(x: isOn ? (trackWidth - knobSize - knobPadding) / 2 : -(trackWidth - knobSize - knobPadding) / 2)
            }
            .opacity(enabled ? 1.0 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Plink Toggle Row (icon + title + subtitle + toggle)
/// 🔧 PREMIUM ROW: Combined row with icon, title, subtitle, and PlinkToggle.
/// Styled like iOS Settings — icon in colored rounded square, two-line text,
/// toggle on the right. No divider gaps — clean continuous card.
struct PlinkToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let iconColor: Color
    @Binding var isOn: Bool
    var enabled: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            // Icon in colored rounded square (iOS Settings style)
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            // Title + subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.raveTextPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.raveTextSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            PlinkToggle(isOn: $isOn, enabled: enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Settings Card (grouped, no internal dividers — clean look)
/// 🔧 PREMIUM CARD: Container for grouped settings rows. No internal dividers
/// (was: Divider with leading padding that created "просветы" between rows).
/// Instead, rows sit directly adjacent in a single material card with rounded
/// corners, like iOS Settings / Telegram.
struct PlinkSettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - Settings Section Header
/// Small uppercase label above each card section (like iOS Settings "ACCOUNT").
struct PlinkSectionHeader: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.raveTextSecondary)
            .tracking(0.5)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
    }
}
