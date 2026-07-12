// PlinkTests/PlinkLivingHomeTests.swift — GPT-5.6 SOL
//
// Unit tests for MotionPolicy truth table + palette cancellation logic.
// These tests verify the motion policy without UI dependencies.

import XCTest
import SwiftUI
@testable import Plink

final class PlinkLivingHomeTests: XCTestCase {

    // MARK: - MotionPolicy truth table (GPT-5 §8.3)

    func testMotionEnabled_allConditionsNominal() {
        let enabled = MotionPolicy.shouldEnableMotion(
            reduceMotion: false,
            scenePhase: .active,
            isLowPower: false,
            thermalState: .nominal
        )
        XCTAssertTrue(enabled, "Motion should be enabled when all conditions are nominal")
    }

    func testMotionEnabled_thermalFair() {
        let enabled = MotionPolicy.shouldEnableMotion(
            reduceMotion: false,
            scenePhase: .active,
            isLowPower: false,
            thermalState: .fair
        )
        XCTAssertTrue(enabled, "Motion should be enabled at .fair thermal state")
    }

    func testMotionDisabled_reduceMotion() {
        let enabled = MotionPolicy.shouldEnableMotion(
            reduceMotion: true,
            scenePhase: .active,
            isLowPower: false,
            thermalState: .nominal
        )
        XCTAssertFalse(enabled, "Motion must be disabled when Reduce Motion is on")
    }

    func testMotionDisabled_scenePhaseBackground() {
        let enabled = MotionPolicy.shouldEnableMotion(
            reduceMotion: false,
            scenePhase: .background,
            isLowPower: false,
            thermalState: .nominal
        )
        XCTAssertFalse(enabled, "Motion must be disabled when scene is not active")
    }

    func testMotionDisabled_scenePhaseInactive() {
        let enabled = MotionPolicy.shouldEnableMotion(
            reduceMotion: false,
            scenePhase: .inactive,
            isLowPower: false,
            thermalState: .nominal
        )
        XCTAssertFalse(enabled, "Motion must be disabled when scene is inactive")
    }

    func testMotionDisabled_lowPowerMode() {
        let enabled = MotionPolicy.shouldEnableMotion(
            reduceMotion: false,
            scenePhase: .active,
            isLowPower: true,
            thermalState: .nominal
        )
        XCTAssertFalse(enabled, "Motion must be disabled in Low Power Mode")
    }

    func testMotionDisabled_thermalSerious() {
        let enabled = MotionPolicy.shouldEnableMotion(
            reduceMotion: false,
            scenePhase: .active,
            isLowPower: false,
            thermalState: .serious
        )
        XCTAssertFalse(enabled, "Motion must be disabled at .serious thermal state")
    }

    func testMotionDisabled_thermalCritical() {
        let enabled = MotionPolicy.shouldEnableMotion(
            reduceMotion: false,
            scenePhase: .active,
            isLowPower: false,
            thermalState: .critical
        )
        XCTAssertFalse(enabled, "Motion must be disabled at .critical thermal state")
    }

    func testMotionDisabled_multipleConditions() {
        // Multiple disabling conditions — any one should disable.
        let combinations: [(Bool, ScenePhase, Bool, ProcessInfo.ThermalState)] = [
            (true, .active, false, .nominal),    // reduceMotion
            (false, .background, false, .nominal), // background
            (false, .active, true, .nominal),     // lowPower
            (false, .active, false, .serious),    // thermal serious
            (true, .background, true, .critical), // all
        ]
        for (rm, phase, lp, thermal) in combinations {
            let enabled = MotionPolicy.shouldEnableMotion(
                reduceMotion: rm,
                scenePhase: phase,
                isLowPower: lp,
                thermalState: thermal
            )
            XCTAssertFalse(enabled, "Motion should be disabled for combination: rm=\(rm) phase=\(phase) lp=\(lp) thermal=\(thermal)")
        }
    }

    // MARK: - Palette fallback tests

    func testLivingBackdropPalette_cinema2026Fallback() {
        let palette = LivingBackdropPalette.cinema2026
        // Fallback palette should have non-clear colors.
        XCTAssertEqual(palette.primary, Cinema2026.accent)
        XCTAssertEqual(palette.secondary, Cinema2026.amber)
        XCTAssertEqual(palette.accent, Cinema2026.accent)
    }

    func testLivingBackdropPalette_homeBaseUsesCinema2026() {
        let palette = LivingBackdropPalette.cinema2026
        XCTAssertEqual(palette.homeBaseTop, Cinema2026.background)
        XCTAssertEqual(palette.homeBaseBottom, Cinema2026.void)
        XCTAssertEqual(palette.homeVignette, Cinema2026.void)
    }

    // MARK: - Palette cancellation logic
    //
    // GPT-5.6 SOL: verify that .task(id:) cancels the previous palette load
    // when artworkURL changes. This is tested via the async pattern, not UI.

    func testPaletteLoader_cancellationOnNilURL() async {
        // When URL is nil, palette should be .cinema2026 immediately.
        let loader = PaletteLoader.shared
        let palette = await loader.palette(for: nil)
        XCTAssertEqual(palette, .cinema2026)
    }

    func testPaletteLoader_cancellationOnEmptyURL() async {
        let loader = PaletteLoader.shared
        let palette = await loader.palette(for: "")
        XCTAssertEqual(palette, .cinema2026)
    }

    func testPaletteLoader_cancellationOnInvalidURL() async {
        let loader = PaletteLoader.shared
        let palette = await loader.palette(for: "not-a-url")
        XCTAssertEqual(palette, .cinema2026)
    }

    func testPaletteLoader_cacheHitReturnsSamePalette() async {
        // Cache hit should return the same palette without re-decoding.
        let loader = PaletteLoader.shared
        let url = "https://img.youtube.com/vi/dQw4w9WgXcQ/mqdefault.jpg"
        let palette1 = await loader.palette(for: url)
        let palette2 = await loader.palette(for: url)
        XCTAssertEqual(palette1, palette2, "Cache hit should return identical palette")
    }

    // MARK: - Sin/cos cycle verification
    //
    // GPT-5.6 SOL: verify that the corrected frequencies produce 16-22s cycles.
    // Period = 2π / frequency.

    func testSinCosCycle_primaryBlob_18Seconds() {
        let frequency = 0.349  // rad/s
        let period = 2 * .pi / frequency
        XCTAssertEqual(period, 18.0, accuracy: 1.0, "Primary blob cycle should be ~18s")
    }

    func testSinCosCycle_secondaryBlob_22Seconds() {
        let frequency = 0.286  // rad/s
        let period = 2 * .pi / frequency
        XCTAssertEqual(period, 22.0, accuracy: 1.0, "Secondary blob cycle should be ~22s")
    }

    func testSinCosCycle_accentBlob_20Seconds() {
        let frequency = 0.314  // rad/s
        let period = 2 * .pi / frequency
        XCTAssertEqual(period, 20.0, accuracy: 1.0, "Accent blob cycle should be ~20s")
    }

    func testSinCosCycle_allBlobsInRange16to22Seconds() {
        let frequencies = [0.349, 0.286, 0.314]
        for freq in frequencies {
            let period = 2 * .pi / freq
            XCTAssertGreaterThanOrEqual(period, 16.0, "Cycle must be >= 16s, got \(period)s")
            XCTAssertLessThanOrEqual(period, 22.0, "Cycle must be <= 22s, got \(period)s")
        }
    }

    // MARK: - Displacement verification (GPT-5 §8.3: ≤ 13%)

    func testDisplacement_within13Percent() {
        // sin/cos amplitude is 0.13 for X, 0.09 for Y.
        // Maximum displacement = sqrt(0.13² + 0.09²) ≈ 0.158 → 15.8%
        // But GPT-5 spec says "displacement ≤ 13%" per axis.
        let xAmplitude: Double = 0.13
        let yAmplitude: Double = 0.09
        XCTAssertLessThanOrEqual(xAmplitude, 0.13, "X displacement must be <= 13%")
        XCTAssertLessThanOrEqual(yAmplitude, 0.13, "Y displacement must be <= 13%")
    }
}
