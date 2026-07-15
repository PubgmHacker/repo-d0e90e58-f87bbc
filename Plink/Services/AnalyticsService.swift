// Simple Analytics stub (Firebase/Mixpanel ready)
// Track key events for P1.

import Foundation

final class AnalyticsService {
    static let shared = AnalyticsService()

    func track(_ event: String, parameters: [String: Any] = [:]) {
        print("[Analytics] \(event) \(parameters)")
        // TODO: FirebaseAnalytics.logEvent(event, parameters: parameters)
    }

    func roomCreated() { track("room_created") }
    func roomJoined() { track("room_joined") }
    func messageSent() { track("message_sent") }
    func themeChanged(_ theme: String) { track("theme_changed", parameters: ["theme": theme]) }
    func aiUsed() { track("ai_chat_used") }
    func premiumPurchased() { track("premium_purchased") }
}