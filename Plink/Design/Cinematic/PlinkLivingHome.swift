// Plink/Design/Cinematic/PlinkLivingHome.swift — GPT-5 Living Home Concept
//
// GPT-5.6 SOL fixes applied:
//   1. sin/cos cycle corrected to 16-22s (frequencies 0.286-0.349 rad/s)
//   2. Low Power/thermal observed dynamically via .onChange + NotificationCenter
//   3. Reduce Transparency disables Canvas blur (uses solid color overlay)
//   4. Removed nested Task inside .task(id:) — direct await
//   5. Unit tests for motion policy + cancellation (separate test file)
//
// GPT-5 spec compliance (§8):
//   - Reuses existing PaletteLoader + LivingBackdropPalette (no duplication)
//   - Canvas + TimelineView at 24fps max
//   - 3 aurora blobs, displacement ≤ 13%, opacity 0.34
//   - Motion policy: Reduce Motion / Low Power / thermal / scenePhase
//   - Palette crossfade 0.55s with cancellation on hero change
//   - No YouTube/WKWebView/DRM frame capture

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
    @State private var lowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    /// GPT-5.6 SOL fix: motion policy evaluated from observed state (not just computed).
    /// Changes to lowPowerMode/thermalState trigger re-render via @State.
    private var motionEnabled: Bool {
        guard !reduceMotion, scenePhase == .active else { return false }
        guard !lowPowerMode else { return false }
        switch thermalState {
        case .serious, .critical: return false
        default: return true
        }
    }

    var body: some View {
        ZStack {
            LivingHomeCanvas(
                palette: palette,
                motionEnabled: motionEnabled,
                reduceTransparency: reduceTransparency
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            content()
        }
        // GPT-5.6 SOL fix: direct await in .task(id:) — no nested Task.
        // SwiftUI automatically cancels the previous .task when id changes.
        .task(id: artworkURL?.absoluteString) {
            await updatePalette()
        }
        // GPT-5.6 SOL fix: observe Low Power Mode changes dynamically.
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        // GPT-5.6 SOL fix: observe thermal state changes dynamically.
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            thermalState = ProcessInfo.processInfo.thermalState
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
        // GPT-5.6 SOL fix: Reduce Transparency → use opaque overlay instead of blur.
        // Canvas blur is expensive; when reduceTransparency is true, skip aurora
        // and use a single solid color overlay for depth.
        .overlay {
            if reduceTransparency {
                // Opaque graphite surface — no blur, no transparency.
                Rectangle()
                    .fill(Cinema2026.surface.opacity(0.6))
            } else {
                // Subtle ultraThinMaterial for depth.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.08)
            }
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

    /// GPT-5.6 SOL fix: sin/cos cycle corrected to 16-22s.
    ///
    /// Period = 2π / frequency. For 16-22s cycle:
    ///   - 18s → freq = 2π/18 ≈ 0.349 rad/s
    ///   - 22s → freq = 2π/22 ≈ 0.286 rad/s
    ///   - 20s → freq = 2π/20 ≈ 0.314 rad/s
    ///
    /// Previous frequencies (0.17, 0.13, 0.11) gave 37-57s cycles — too slow.
    private func drawAurora(
        in context: inout GraphicsContext,
        size: CGSize,
        date: Date
    ) {
        let t = motionEnabled ? date.timeIntervalSinceReferenceDate : 0
        let amount: CGFloat = motionEnabled ? 1 : 0

        // GPT-5.6 SOL: corrected frequencies for 18-22s cycles.
        let blobs: [(Color, CGPoint, CGFloat, Double)] = [
            (palette.primary, CGPoint(x: 0.08, y: 0.10), 0.76, 0.349),  // 18s cycle
            (palette.secondary, CGPoint(x: 0.90, y: 0.34), 0.72, 0.286),  // 22s cycle
            (palette.accent, CGPoint(x: 0.45, y: 0.92), 0.78, 0.314)   // 20s cycle
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

            // GPT-5.6 SOL fix: skip blur entirely when reduceTransparency is true.
            if reduceTransparency {
                // Solid color fill, no blur — cheaper and respects accessibility.
                context.opacity = 0.20
                context.fill(Path(ellipseIn: rect), with: .color(blob.0))
                context.opacity = 1.0
            } else {
                context.drawLayer { layer in
                    // GPT-5: blur radius max(42, diameter * 0.12).
                    layer.addFilter(.blur(radius: max(42, diameter * 0.12)))
                    // GPT-5: opacity 0.24-0.36 (using 0.34 as mid-point).
                    layer.opacity = 0.34
                    layer.fill(Path(ellipseIn: rect), with: .color(blob.0))
                }
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

extension LivingBackdropPalette {
    /// GPT-5: Home-specific palette with Cinema2026 base + artwork accents.
    var homeBaseTop: Color { Cinema2026.background }
    var homeBaseBottom: Color { Cinema2026.void }
    var homeVignette: Color { Cinema2026.void }
}

// MARK: - State matrix helpers (GPT-5 §8.6)

@available(iOS 17.0, *)
struct LivingHomeStateOverlay: View {
    /// GPT-5 §8.6: loading state shows stable skeleton geometry over fallback backdrop.
    let isLoading: Bool

    var body: some View {
        if isLoading {
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

// MARK: - MotionPolicy (testable)
//
// GPT-5.6 SOL: extracted as a pure function for unit testing.
// Tests can verify the truth table without UI dependencies.

enum MotionPolicy {
    /// Evaluate whether motion should be enabled given the current state.
    /// - Parameters:
    ///   - reduceMotion: Accessibility Reduce Motion setting.
    ///   - scenePhase: Current scene phase (must be .active).
    ///   - isLowPower: ProcessInfo.isLowPowerModeEnabled.
    ///   - thermalState: ProcessInfo.thermalState.
    /// - Returns: true if motion is allowed.
    static func shouldEnableMotion(
        reduceMotion: Bool,
        scenePhase: ScenePhase,
        isLowPower: Bool,
        thermalState: ProcessInfo.ThermalState
    ) -> Bool {
        guard !reduceMotion else { return false }
        guard scenePhase == .active else { return false }
        guard !isLowPower else { return false }
        switch thermalState {
        case .serious, .critical: return false
        case .nominal, .fair: return true
        @unknown default: return true
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
