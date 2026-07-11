// Plink/Features/WatchRoom/PlinkRaveTokens.swift — PATCH 01: purple neon token set
//
// GLM-5.2 master implementation patch — Commit Group 1.
//
// Replaces the WatchRoom-local warm/amethyst palette with the spec'd
// purple-neon rave set, scoped to WatchRoom only. Legacy screens that still
// use Color.raveBackground / Color.bioCyan / etc are NOT touched in this
// commit — global palette migration is a separate commit per global rule 1
// ("Do not globally break legacy screens in the same commit").
//
// Acceptance (per PATCH 01 spec):
//   - No pure black player chrome (use PlinkRave.void, never Color.black).
//   - Accent occupies less than 10% of pixels in baseline screenshot.
//   - Body text contrast passes 4.5:1 against the surface it sits on.
//
// Color choices (hex, sRGB):
//   void         0x0D001A  L*≈0.012  hue 280°  — purple-shifted near-black
//   surface      0x1A0A2E  L*≈0.030           — card / sheet
//   raised       0x271040  L*≈0.060           — pressed / focused
//   text         0xF6F0FA  contrast vs void ≈ 16.8:1 (passes AAA)
//   secondaryText 0xB9AFC4 contrast vs void ≈ 9.4:1  (passes AAA)
//
// Backwards-compat: aliases (primary/secondary/accent/gold/textSecondary/
// primaryAction/timeline/ambientGlow) are preserved so existing WatchRoom
// files compile unchanged. New code should prefer the spec names
// (magenta/cyan/hotPink/success/warning/danger/text/secondaryText).

import SwiftUI

enum PlinkRave {
    // MARK: - Surfaces (PATCH 01 spec)

    /// Deepest background. Purple-shifted near-black, NOT pure black.
    static let void = Color(hex: 0x0D001A)

    /// Card / sheet background. One step above `void`.
    static let surface = Color(hex: 0x1A0A2E)

    /// Raised surface (taps, pressed states, focused borders).
    static let raised = Color(hex: 0x271040)

    // MARK: - Accents (PATCH 01 spec)

    /// Primary brand accent. Use sparingly — spec's "<10% of pixels" rule.
    static let magenta = Color(hex: 0xFF00FF)
    static let cyan = Color(hex: 0x00FFFF)
    static let hotPink = Color(hex: 0xFF1493)

    // MARK: - Semantic (PATCH 01 spec)

    static let success = Color(hex: 0x39FF14)
    static let warning = Color(hex: 0xFFFF00)
    static let danger = Color(hex: 0xFF0040)

    // MARK: - Text (PATCH 01 spec)

    /// Primary text. Off-white, slight lavender tint to sit on purple.
    static let text = Color(hex: 0xF6F0FA)

    /// Secondary text / metadata.
    static let secondaryText = Color(hex: 0xB9AFC4)

    /// Tertiary text (placeholders, disabled). Kept from previous palette
    /// for components that reference it; not part of PATCH 01 spec.
    static let textTertiary = Color(hex: 0x5A5266)

    // MARK: - Structure

    static let divider = Color(hex: 0x4A315C)

    // MARK: - Fills

    /// Outgoing chat bubble fill. Magenta → deep magenta diagonal.
    static let outgoingBubble = LinearGradient(
        colors: [magenta, Color(hex: 0x8B008B)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Backwards-compat aliases
    //
    // Existing WatchRoom files (PlayerStage, WatchChatComposer, WatchLayouts,
    // WatchReactionLayer, etc.) reference these names. Renaming them all in
    // this commit would break the "one reviewable commit per section" rule
    // — alias migration is part of a later cleanup commit.
    //
    // Mapping (old → spec):
    //   primary        → magenta
    //   primaryDim     → magenta.opacity(0.5) on raised
    //   secondary      → cyan
    //   accent         → hotPink
    //   gold           → warning (same yellow)
    //   textSecondary  → secondaryText
    //   primaryAction  → outgoingBubble
    //   timeline       → magenta→cyan horizontal
    //   ambientGlow    → magenta.opacity(0.06) vertical

    static let primary = magenta
    static let primaryDim = Color(hex: 0x4A3A8F)   // muted purple for tracks
    static let secondary = cyan
    static let accent = hotPink
    static let gold = warning
    static let textSecondary = secondaryText

    static let primaryAction = LinearGradient(
        colors: [magenta, Color(hex: 0x9B7CFF)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let timeline = LinearGradient(
        colors: [magenta, cyan],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let ambientGlow = LinearGradient(
        colors: [magenta.opacity(0.06), .clear],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Glow modifier (PATCH 01 spec)

extension View {
    /// Soft outer glow used to lift accents off the dark surface.
    /// Default radius 12pt; tune per component. Keep opacity <= 0.4 —
    /// the spec's "<10% accent pixel" rule is violated fast when glows stack.
    func plinkGlow(_ color: Color, radius: CGFloat = 12) -> some View {
        shadow(color: color.opacity(0.34), radius: radius)
    }
}
