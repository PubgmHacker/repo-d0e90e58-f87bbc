// Plink/Features/WatchRoom/Reactions/ReactionPickerView.swift — Commit Group 6
//
// Popover-style reaction picker shown when the user taps the emoji button
// in WatchChatComposer. Renders a 4-column grid of all emojis (free +
// premium), with premium emojis carrying a star badge and gated tap.
//
// Design:
//   - 4 columns, scrollable vertically, ~6 rows visible at once
//   - Free emojis: 32pt glyph in 44pt cell, no badge
//   - Premium emojis: 32pt glyph + 10pt star badge bottom-right, dimmed
//     when user has no entitlement
//   - Tap on free emoji → onPick(emoji)
//   - Tap on premium emoji + hasPremium → onPick(emoji)
//   - Tap on premium emoji + !hasPremium → onPremiumUpsell()
//   - Background: Cinema2026.surface.opacity(0.95) with .ultraThinMaterial
//     overlay for depth
//   - Corner radius: 18pt
//   - Max height: 280pt (keeps popover compact on portrait)
//
// Accessibility:
//   - Each emoji cell has accessibilityLabel "Emoji <glyph>, free" or
//     "Emoji <glyph>, premium"
//   - Premium cells have accessibilityHint "Subscribe to Plink+ to send
//     this reaction"
//
// The picker does NOT own state — it's a pure presentation component.
// The owner (WatchRoomScreen via .popover or .sheet) decides when to
// show/hide and wires onPick / onPremiumUpsell.

import SwiftUI

struct ReactionPickerView: View {
    let hasPremium: Bool
    let onPick: (String) -> Void
    let onPremiumUpsell: () -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 4
    )

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Reactions")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                Spacer()
                if !hasPremium {
                    Button(action: onPremiumUpsell) {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                            Text("Plink+")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Cinema2026.amber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Cinema2026.amber.opacity(0.12), in: Capsule())
                    }
                    .accessibilityLabel("Unlock Plink+ reactions")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // Emoji grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(ReactionPalette.all, id: \.self) { emoji in
                        cell(for: emoji)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
        }
        .frame(maxHeight: 280)
        .background(Cinema2026.surface.opacity(0.95))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Cinema2026.divider.opacity(0.4), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func cell(for emoji: String) -> some View {
        let tier = ReactionPalette.tier(for: emoji)
        let isPremium = tier == .premium
        let isLocked = isPremium && !hasPremium

        Button {
            if isLocked {
                onPremiumUpsell()
            } else {
                onPick(emoji)
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Text(emoji)
                    .font(.system(size: 32))
                    .frame(width: 44, height: 44)
                    .opacity(isLocked ? 0.45 : 1.0)

                if isPremium {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Cinema2026.amber)
                        .padding(3)
                        .background(Cinema2026.background, in: Circle())
                        .offset(x: 2, y: 2)
                }
            }
            .frame(width: 56, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.05), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Emoji \(emoji), \(isPremium ? "premium" : "free")")
        .accessibilityHint(isLocked ? "Subscribe to Plink+ to send this reaction" : "")
    }
}

#if DEBUG
#Preview {
    ReactionPickerView(
        hasPremium: false,
        onPick: { _ in },
        onPremiumUpsell: {}
    )
    .padding()
    .background(Cinema2026.background)
}
#endif
