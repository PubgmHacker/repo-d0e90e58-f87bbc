// Plink/Design/Cinematic/PlinkLivingHome.swift — GPT-5 Living Home Concept
//
// GPT-5 IOS living Home integration patch.
// Adapted from PlinkLivingHomeConcept.swift to use the EXISTING:
//   - PaletteLoader actor (Plink/Design/Cinematic/PaletteLoader.swift)
//   - LivingBackdropPalette struct (Plink/Design/Cinematic/CompactLivingBackdrop.swift)
//   - Cinema2026 enum (Plink/Design/Cinematic/CompactPhoneMetrics.swift)
//
// GPT-5 spec: "delete the standalone loader in production and reuse the
// existing PaletteLoader actor and LivingBackdropPalette extraction/cache.
// Do not create duplicate image downloads, caches or palette algorithms."
//
// This file provides:
//   1. PlinkLivingHome<Content> — wrapper that binds artwork URL → palette
//   2. LivingHomeCanvas — Canvas-based animated backdrop (24fps, 3 aurora blobs)
//   3. LivingHomePalette extension — maps LivingBackdropPalette → 6-color palette
//
// Motion policy (GPT-5 §8.3):
//   - 16-22s non-repeating drift, transforms + opacity only
//   - 24 fps max (TimelineView .animation(minimumInterval: 1/24))
//   - displacement ≤ 13%, opacity 0.24-0.36
//   - freeze for Reduce Motion, inactive scene, Low Power, thermal ≥ serious
//   - palette crossfade 0.55s, cancelled on hero change
//   - no YouTube/WKWebView/DRM frame capture

import SwiftUI
import UIKit

// MARK: - PlinkLivingHome wrapper
//
// Usage in HomeView:
//   PlinkLivingHome(artworkURL: heroThumbnailURL) {
//       // existing HomeView content
//       ScrollView { ... }
//   }

@available(iOS 17.0, *)
struct PlinkLivingHome<Content: View>: View {
    let artworkURL: URL?
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase

    @State private var palette: LivingBackdropPalette = .cinema2026
    @State private var paletteTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            LivingHomeCanvas(
                palette: palette,
                motionEnabled: motionEnabled,
                reduceTransparency: reduceTransparency
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)  // GPT-5: background hidden from VoiceOver

            content()
        }
        // GPT-5: one palette task per selected hero, canceled on change/disappear.
        .task(id: artworkURL?.absoluteString) {
            paletteTask?.cancel()
            paletteTask = Task { await updatePalette() }
            await paletteTask?.value
        }
        .onDisappear {
            paletteTask?.cancel()
            paletteTask = nil
        }
    }

    /// GPT-5 §8.3 motion policy truth table.
    private var motionEnabled: Bool {
        guard !reduceMotion, scenePhase == .active else { return false }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return false }
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: return false
        default: return true
        }
    }

    @MainActor
    private func updatePalette() async {
        guard let artworkURL else {
            withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.55)) {
                palette = .cinema2026
            }
            return
        }

        // GPT-5: reuse existing PaletteLoader — no duplicate cache/pipeline.
        let loaded = await PaletteLoader.shared.palette(for: artworkURL.absoluteString)
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.55)) {
            palette = loaded
        }
    }
}

// MARK: - LivingHomeCanvas
//
// GPT-5 §8.2: "one base gradient plus three large blurred fields"
// Rendered via Canvas at 24fps max (TimelineView .animation(minimumInterval: 1/24)).

@available(iOS 17.0, *)
struct LivingHomeCanvas: View {
    let palette: LivingBackdropPalette
    let motionEnabled: Bool
    let reduceTransparency: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: motionEnabled ? 1.0 / 24.0 : 60)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                drawBase(in: &context, size: size)
                drawAurora(in: &context, size: size, date: timeline.date)
                drawVignette(in: &context, size: size)
            }
        }
        .overlay {
            // GPT-5: subtle ultraThinMaterial for depth (disabled in Reduce Transparency).
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(reduceTransparency ? 0 : 0.08)
        }
    }

    /// GPT-5: graphite Cinema2026 base gradient (top → bottom).
    private func drawBase(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [Cinema2026.background, Cinema2026.void]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: size.height)
            )
        )
    }

    /// GPT-5 §8.3: three aurora blobs — primary, secondary, accent.
    /// Displacement ≤ 13%, opacity 0.24-0.36, blur radius max(42, diameter * 0.12).
    private func drawAurora(
        in context: inout GraphicsContext,
        size: CGSize,
        date: Date
    ) {
        let t = motionEnabled ? date.timeIntervalSinceReferenceDate : 0
        let amount: CGFloat = motionEnabled ? 1 : 0

        // Map LivingBackdropPalette (3 colors) → 3 blobs.
        let blobs: [(Color, CGPoint, CGFloat, Double)] = [
            (palette.primary, CGPoint(x: 0.08, y: 0.10), 0.76, 0.17),
            (palette.secondary, CGPoint(x: 0.90, y: 0.34), 0.72, 0.13),
            (palette.accent, CGPoint(x: 0.45, y: 0.92), 0.78, 0.11)
        ]

        for (index, blob) in blobs.enumerated() {
            // GPT-5: displacement ≤ 13%.
            let offsetX = sin(t * blob.3 + Double(index) * 1.7) * 0.13 * amount
            let offsetY = cos(t * blob.3 * 0.8 + Double(index)) * 0.09 * amount
            let diameter = max(size.width, size.height) * blob.2
            let center = CGPoint(
                x: size.width * (blob.1.x + offsetX),
                y: size.height * (blob.1.y + offsetY)
            )
            let rect = CGRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter
            )

            context.drawLayer { layer in
                // GPT-5: blur radius max(42, diameter * 0.12).
                layer.addFilter(.blur(radius: max(42, diameter * 0.12)))
                // GPT-5: opacity 0.24-0.36 (using 0.34 as mid-point).
                layer.opacity = 0.34
                layer.fill(Path(ellipseIn: rect), with: .color(blob.0))
            }
        }
    }

    /// GPT-5: bottom vignette to preserve tab-bar and rail contrast.
    private func drawVignette(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0.34),
                    .init(color: Cinema2026.void.opacity(0.28), location: 0.68),
                    .init(color: Cinema2026.void.opacity(0.92), location: 1)
                ]),
                startPoint: CGPoint(x: size.width / 2, y: 0),
                endPoint: CGPoint(x: size.width / 2, y: size.height)
            )
        )
    }
}

// MARK: - LivingBackdropPalette extension for Home
//
// GPT-5: the existing LivingBackdropPalette (3 colors) is sufficient for Home.
// The concept's 6-color palette (baseTop, baseBottom, primary, secondary,
// accent, vignette) is mapped here: baseTop/baseBottom/vignette use Cinema2026
// constants, primary/secondary/accent come from the artwork extraction.

extension LivingBackdropPalette {
    /// GPT-5: Home-specific palette with Cinema2026 base + artwork accents.
    /// Used by LivingHomeCanvas for the 3 aurora blobs.
    /// Base gradient and vignette use Cinema2026 constants (not artwork-derived)
    /// to maintain legibility and brand consistency.
    var homeBaseTop: Color { Cinema2026.background }
    var homeBaseBottom: Color { Cinema2026.void }
    var homeVignette: Color { Cinema2026.void }
}

// MARK: - State matrix helpers (GPT-5 §8.6)
//
// GPT-5 requires: loading, loaded, empty, offline, API error, no artwork,
// Reduce Motion, Reduce Transparency, Low Power/thermal, Dynamic Type XXXL, VoiceOver.
// These states are handled by the host view (HomeView) — PlinkLivingHome only
// provides the backdrop. The host view provides skeleton/empty/offline content.

@available(iOS 17.0, *)
struct LivingHomeStateOverlay: View {
    /// GPT-5 §8.6: loading state shows stable skeleton geometry over fallback backdrop.
    let isLoading: Bool

    var body: some View {
        if isLoading {
            // Skeleton shimmer — stable geometry, no content jump.
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Cinema2026.surface.opacity(0.4))
                    .frame(height: 280)
                    .padding(.horizontal, 14)
                ForEach(0..<2, id: \.self) { _ in
                    HStack {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Cinema2026.surface.opacity(0.3))
                                .frame(width: 140, height: 80)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
            .redacted(reason: .placeholder)
            .accessibilityLabel("Загрузка ленты")
        }
    }
}

#Preview {
    if #available(iOS 17.0, *) {
        PlinkLivingHome(artworkURL: nil) {
            ScrollView {
                VStack(spacing: 24) {
                    Text("С кем смотрим?")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Cinema2026.text)
                        .padding(.top, 60)
                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
