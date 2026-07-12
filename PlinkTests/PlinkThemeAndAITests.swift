// PlinkTests/PlinkThemeAndAITests.swift — GPT-5.6 §16
import XCTest
@testable import Plink

final class PlinkThemeTests: XCTestCase {

    func testAllFiveThemesResolve() {
        let ids = ["electric-blue", "cinema-ember", "violet-horizon", "plink-teal", "magenta-bloom"]
        for id in ids {
            let theme = PlinkThemeCatalog.resolve(id)
            XCTAssertEqual(theme.id, id, "Theme \(id) should resolve")
        }
    }

    func testUnknownIDFallsBackSafely() {
        let theme = PlinkThemeCatalog.resolve("nonexistent")
        XCTAssertEqual(theme.id, "electric-blue", "Unknown ID should fall back to electric-blue")
    }

    func testNilIDFallsBackSafely() {
        let theme = PlinkThemeCatalog.resolve(nil)
        XCTAssertEqual(theme.id, "electric-blue", "Nil ID should fall back to electric-blue")
    }

    func testFreeThemesAccessible() {
        let free = PlinkThemeCatalog.all.filter { $0.access == .free }
        XCTAssertGreaterThanOrEqual(free.count, 1, "At least one free theme required")
    }

    func testPremiumThemesExist() {
        let premium = PlinkThemeCatalog.all.filter { $0.access == .premium }
        XCTAssertGreaterThanOrEqual(premium.count, 1, "At least one premium theme required")
    }

    func testThemeStoreSelectFreeTheme() throws {
        let store = PlinkThemeStore()
        try store.selectAppTheme(id: "electric-blue", hasPremium: false)
        XCTAssertEqual(store.appTheme.id, "electric-blue")
    }

    func testThemeStoreRejectsPremiumWithoutEntitlement() {
        let store = PlinkThemeStore()
        XCTAssertThrowsError(try store.selectAppTheme(id: "cinema-ember", hasPremium: false))
    }

    func testThemeStoreAllowsPremiumWithEntitlement() throws {
        let store = PlinkThemeStore()
        try store.selectAppTheme(id: "cinema-ember", hasPremium: true)
        XCTAssertEqual(store.appTheme.id, "cinema-ember")
    }
}

final class PlinkAITests: XCTestCase {

    func testAIMessageCreation() {
        let msg = PlinkAIMessage(role: .user, text: "Hello")
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.text, "Hello")
    }

    func testAIVisualStatesExist() {
        let states: [PlinkAIVisualState] = [.idle, .listening, .thinking, .speaking, .moderating, .offline, .failed]
        XCTAssertEqual(states.count, 7)
    }

    func testAIActionEncodeDecode() {
        let actions: [AIAction] = [.retry, .previewQueue(["a", "b"]), .confirmCreateRoom(draftID: "x"), .confirmInvite(userIDs: ["1"])]
        XCTAssertEqual(actions.count, 4)
    }
}

final class LivingMotionPolicyTests: XCTestCase {

    func testMotionAllowedAllNominal() {
        let policy = LivingMotionPolicy()
        XCTAssertTrue(policy.allowsMotion(reduceMotion: false, scenePhase: .active))
    }

    func testMotionDisabledReduceMotion() {
        let policy = LivingMotionPolicy()
        XCTAssertFalse(policy.allowsMotion(reduceMotion: true, scenePhase: .active))
    }

    func testMotionDisabledBackgroundScene() {
        let policy = LivingMotionPolicy()
        XCTAssertFalse(policy.allowsMotion(reduceMotion: false, scenePhase: .background))
    }
}
