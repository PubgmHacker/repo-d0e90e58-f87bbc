import SwiftUI

// ═══════════════════════════════════════════════════════════════════════
// MARK: - Bubble Style Picker (Premium Feature — v10 July 2026)
// ═══════════════════════════════════════════════════════════════════════
//
// Lets Плинк+ subscribers pick a custom chat bubble style. The selected
// style is stored locally (BubbleStylePreference) and sent as a HINT to
// the server on every outgoing message.
//
// Permission logic:
//   - Non-premium users: see only the "default" style. Tapping locked
//     styles opens the paywall.
//   - Premium users: see default + cute_duck + neon_cyber. Selectable.
//   - Admins: see the same picker as premium users, but their selection
//     is IGNORED server-side (admin_bubble is always applied). We show
//     a banner explaining this.
//
// Note: admin_bubble is NOT shown in the picker — it's auto-applied by
// the server to admins and can't be turned off, so showing it as a
// "selectable" option would be misleading.

struct BubbleStylePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Caller provides user's permission context. The picker doesn't
    /// query PremiumStatusManager itself — keeps it pure / testable.
    let isPremium: Bool
    let isAdmin: Bool

    /// Closure called when user selects an unlocked style. Caller persists
    /// via BubbleStylePreference.set().
    var onPick: (BubbleStyle) -> Void

    /// Closure called when user taps a locked style (non-premium).
    var onLockedTap: () -> Void

    @State private var selectedStyle: BubbleStyle = BubbleStylePreference.get()

    private var permissions: BubbleStylePermissions {
        BubbleStylePermissions(isPremium: isPremium, isAdmin: isAdmin)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BioluminescentBackground(energy: 0.6, dimming: 0, palette: .amber)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        if isAdmin {
                            adminBanner
                        }

                        // All 4 styles shown (admin_bubble too — for preview).
                        // Locked ones are greyed out and tapping opens paywall.
                        ForEach(BubbleStyle.allCases) { style in
                            styleRow(style)
                        }

                        // Footer note
                        Text("Стиль применяется к вашим сообщениям в комнатах совместного просмотра. Сервер проверяет права — даже если приложение модифицировано, Unauthorized стили будут сброшены к «Стандартный».")
                            .font(.system(size: 11))
                            .foregroundColor(.raveTextTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Стили пузырей")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundColor(.bioAmber)
                }
            }
            .toolbarBackground(Color.clear, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Admin Banner

    private var adminBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Вы администратор")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text("Ваши сообщения всегда используют VIP-стиль автоматически. Выбор ниже — только для предпросмотра.")
                    .font(.system(size: 11))
                    .foregroundColor(.raveTextSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Style Row

    @ViewBuilder
    private func styleRow(_ style: BubbleStyle) -> some View {
        let canSelect = permissions.canSelect(style)
        let isSelected = selectedStyle == style

        Button {
            if canSelect {
                HapticManager.impact(.light)
                selectedStyle = style
                BubbleStylePreference.set(style)
                onPick(style)
            } else {
                HapticManager.impact(.heavy)
                onLockedTap()
            }
        } label: {
            HStack(spacing: 12) {
                // Preview bubble
                previewBubble(style)
                    .frame(width: 60, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(style.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(canSelect ? .raveTextPrimary : .raveTextSecondary)
                        if !canSelect && style != .adminBubble {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.raveTextTertiary)
                        }
                        if style == .adminBubble {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                        }
                    }
                    Text(style.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.raveTextSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected && canSelect {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.bioAmber)
                } else if !canSelect && style != .adminBubble {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(.bioAmber)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected && canSelect
                            ? Color.bioAmber.opacity(0.6)
                            : Color.white.opacity(0.06),
                        lineWidth: isSelected && canSelect ? 1.5 : 0.5
                    )
            )
            .opacity(canSelect || style == .adminBubble ? 1.0 : 0.55)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    /// Mini preview of a bubble (for the picker row)
    @ViewBuilder
    private func previewBubble(_ style: BubbleStyle) -> some View {
        let previewText = "Привет!"
        switch style {
        case .default:
            Text(previewText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.raveCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        case .cuteDuck:
            ZStack {
                Text(previewText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.5, green: 0.3, blue: 0.0))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.85, blue: 0.30), Color(red: 1.0, green: 0.70, blue: 0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Image(systemName: "bird.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.0))
                    .offset(x: 22, y: -16)
            }
        case .neonCyber:
            Text(previewText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            LinearGradient(
                                colors: [Color.cyan, Color.pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        case .adminBubble:
            Text(previewText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(red: 0.04, green: 0.04, blue: 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.95, green: 0.75, blue: 0.20),
                                    Color(red: 0.70, green: 0.50, blue: 0.10),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - Preview
// ═══════════════════════════════════════════════════════════════════════

#Preview("Premium User") {
    BubbleStylePickerSheet(
        isPremium: true,
        isAdmin: false,
        onPick: { _ in },
        onLockedTap: {}
    )
}

#Preview("Admin User") {
    BubbleStylePickerSheet(
        isPremium: true,
        isAdmin: true,
        onPick: { _ in },
        onLockedTap: {}
    )
}

#Preview("Non-Premium User") {
    BubbleStylePickerSheet(
        isPremium: false,
        isAdmin: false,
        onPick: { _ in },
        onLockedTap: {}
    )
}
