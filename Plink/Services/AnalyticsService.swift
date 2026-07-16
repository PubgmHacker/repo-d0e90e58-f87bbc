// Analytics — Firebase + console. Core funnel for MVP beta.

import Foundation
import FirebaseAnalytics

final class AnalyticsService {
    static let shared = AnalyticsService()

    private init() {}

    func track(_ event: String, parameters: [String: Any] = [:]) {
        var params: [String: Any] = parameters
        params["ts"] = Int(Date().timeIntervalSince1970)
        print("[Analytics] \(event) \(params)")
        // Firebase rejects non-string/number values — sanitize
        let safe = params.compactMapValues { v -> Any? in
            switch v {
            case is String, is Int, is Double, is Float, is Bool: return v
            default: return String(describing: v)
            }
        }
        Analytics.logEvent(event, parameters: safe)
    }

    // MARK: - Lifecycle / auth

    func appOpen() { track("app_open") }
    func signUp() { track("sign_up") }
    func login() { track("login") }
    func logout() { track("logout") }

    // MARK: - Core room loop

    func roomCreated(source: String = "unknown") {
        track("room_created", parameters: ["source": source])
    }
    func roomJoined(via: String = "code") {
        track("room_joined", parameters: ["via": via])
    }
    func roomLeft() { track("room_left") }
    func messageSent() { track("message_sent") }
    func shareRoom() { track("share_room") }
    func inviteFriend() { track("invite_friend") }

    // MARK: - Media / voice / premium

    func voiceChatStarted() { track("voice_chat_started") }
    func themeChanged(_ theme: String) {
        track("theme_changed", parameters: ["theme": theme])
    }
    func emojiUsed(_ pack: String = "default") {
        track("emoji_used", parameters: ["pack": pack])
    }
    func aiUsed() { track("ai_chat_used") }
    func premiumPurchased(productId: String = "") {
        track("premium_purchased", parameters: ["product_id": productId])
    }
    func premiumCanceled() { track("premium_canceled") }

    // MARK: - Sync quality

    func syncDriftMs(_ ms: Int) {
        track("sync_drift", parameters: ["drift_ms": ms])
    }
}
