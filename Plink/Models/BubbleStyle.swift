import Foundation
import SwiftUI

// ═══════════════════════════════════════════════════════════════════════
// MARK: - Chat Bubble Style (v10 — July 2026)
// ═══════════════════════════════════════════════════════════════════════
//
// Three permission tiers, mirrored on the backend (processMessageStyle):
//
//   ┌──────────────────┬──────────┬───────────────┬───────────────────┐
//   │ Style ID         │ Default  │ Плинк+ (paid) │ Admin/Founder     │
//   ├──────────────────┼──────────┼───────────────┼───────────────────┤
//   │ default          │    ✅    │      ✅       │        ❌ (auto)   │
//   │ cute_duck        │    ❌    │      ✅       │        ❌ (auto)   │
//   │ neon_cyber       │    ❌    │      ✅       │        ❌ (auto)   │
//   │ admin_bubble     │    ❌    │      ❌       │        ✅ (forced) │
//   └──────────────────┴──────────┴───────────────┴───────────────────┘
//
// CRITICAL: clients NEVER self-decide the rendered style. The server runs
// `processMessageStyle()` on every incoming message and broadcasts the
// confirmed style id in `bubbleStyle`. Clients must render based on the
// server-confirmed value, NOT on what the local user "thinks" they picked.
//
// Why this matters:
//   - A jailbroken iOS client could send `bubbleStyle: 'admin_bubble'` in
//     the WS payload. The server will downgrade it to 'default' before
//     broadcasting, so other users never see the forged style.
//   - Admins are forced to 'admin_bubble' regardless of what they pick in
//     the UI — this guarantees admin messages are always visually distinct.
//
// The local user's "selected style" (for the picker UI) is sent as a HINT
// to the server. The server's response is the TRUTH.

enum BubbleStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case `default`   = "default"
    case cuteDuck    = "cute_duck"
    case neonCyber   = "neon_cyber"
    case adminBubble = "admin_bubble"

    var id: String { rawValue }

    /// Display name for the picker UI.
    var displayName: String {
        switch self {
        case .`default`:   return "Стандартный"
        case .cuteDuck:    return "Милая уточка"
        case .neonCyber:   return "Неон Кибер"
        case .adminBubble: return "Админ (VIP)"
        }
    }

    /// One-line description shown in the picker.
    var subtitle: String {
        switch self {
        case .`default`:   return "Базовая плашка чата"
        case .cuteDuck:    return "Жёлтый градиент + анимированная уточка"
        case .neonCyber:   return "Киберпанк-неон рамка с пульсацией"
        case .adminBubble: return "Чёрный матовый + золотая неоновая рамка"
        }
    }

    /// SF Symbol icon for the picker.
    var icon: String {
        switch self {
        case .`default`:   return "bubble.left.fill"
        case .cuteDuck:    return "bird.fill"
        case .neonCyber:   return "bolt.fill"
        case .adminBubble: return "crown.fill"
        }
    }

    /// Permission tier required to USE this style (NOT to view — anyone can
    /// view any style, the server may broadcast admin_bubble to all clients).
    /// Used by the picker to grey out locked styles for non-premium users.
    var requiredTier: PermissionTier {
        switch self {
        case .`default`:   return .everyone
        case .cuteDuck,
             .neonCyber:   return .premium
        case .adminBubble: return .admin
        }
    }

    enum PermissionTier: String, Sendable {
        case everyone
        case premium
        case admin
    }

    /// Decode from backend string. Unknown values default to `.default`
    /// — this is a defensive measure in case the backend adds a new style
    /// before the client is updated.
    static func from(_ raw: String?) -> BubbleStyle {
        guard let raw else { return .`default` }
        return BubbleStyle(rawValue: raw) ?? .`default`
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - User Permissions Helper
// ═══════════════════════════════════════════════════════════════════════

/// Determines which styles the current user is ALLOWED to pick in the UI.
/// Note: this is purely for UI greying-out — actual enforcement happens
/// server-side in processMessageStyle().
struct BubbleStylePermissions: Sendable {
    let isPremium: Bool
    let isAdmin: Bool

    /// Styles the user can SELECT in the picker. Admins don't see admin_bubble
    /// in their picker because it's applied automatically — they don't get to
    /// "turn it off", so showing it would be misleading.
    var selectableStyles: [BubbleStyle] {
        if isAdmin {
            // Admins only see default + premium styles in picker — but their
            // selection is IGNORED server-side (admin_bubble is always applied).
            // We still show the picker so admins can preview what other users see.
            return [.default, .cuteDuck, .neonCyber]
        }
        if isPremium {
            return [.default, .cuteDuck, .neonCyber]
        }
        return [.default]
    }

    /// True if the user is allowed to pick this style. Used to grey out
    /// locked cells in the picker.
    func canSelect(_ style: BubbleStyle) -> Bool {
        selectableStyles.contains(style)
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - Local User Preference (UserDefaults)
// ═══════════════════════════════════════════════════════════════════════

/// Persists the user's preferred bubble style across app launches.
/// This is the HINT we send to the server; the server may override it.
enum BubbleStylePreference {
    private static let key = "plink_preferred_bubble_style"

    static func get() -> BubbleStyle {
        let raw = UserDefaults.standard.string(forKey: key) ?? BubbleStyle.`default`.rawValue
        return BubbleStyle(rawValue: raw) ?? .`default`
    }

    static func set(_ style: BubbleStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: key)
    }
}
