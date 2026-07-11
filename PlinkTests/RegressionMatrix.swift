// PlinkTests/RegressionMatrix.swift — PATCH 11
//
// GLM-5.2 master implementation patch — Commit Group 13.
//
// 18-system regression sweep matrix per PATCH 11 spec. Each row requires
// owner, test, telemetry, and status. No "fixed by inspection" for
// runtime systems.
//
// This file is a DOCUMENTATION artifact — it defines the matrix as a
// Swift enum so it can be referenced from tests and CI. The actual test
// coverage lives in the respective *Tests.swift files; this file is the
// authoritative index.
//
// Matrix columns:
//   - system: the functional area under test
//   - owner: who owns the test (team or individual)
//   - testFile: the XCTest file(s) covering this system
//   - telemetry: what metrics are emitted (logs, signposts, analytics)
//   - status: .green (passing), .yellow (partial), .red (failing/missing)
//
// CI usage:
//   - On every PR, run `xcodebuild test` and update status based on results.
//   - The matrix is reviewed at every release.
//   - Any .red status blocks release.

import Foundation

enum RegressionSystem: String, CaseIterable, Identifiable {
    case auth
    case rooms
    case lifecycle
    case websockets
    case playback
    case chat
    case reactions
    case presence
    case sync
    case profile
    case friends
    case dms
    case deeplinks
    case notifications
    case settings
    case gdpr
    case billing
    case admin

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auth:          return "Authentication"
        case .rooms:         return "Room creation / join"
        case .lifecycle:     return "App lifecycle (background/foreground)"
        case .websockets:    return "WebSocket realtime v2"
        case .playback:      return "Playback (YouTube/HLS/MP4/Rutube)"
        case .chat:          return "Chat (text + composer)"
        case .reactions:     return "Reactions (emoji + picker)"
        case .presence:      return "Presence (participants + speaking)"
        case .sync:          return "Sync (clock + ordered controller)"
        case .profile:       return "Profile (edit + avatar)"
        case .friends:       return "Friends (add/remove/list)"
        case .dms:           return "Direct messages"
        case .deeplinks:     return "Deep links (plink://)"
        case .notifications: return "Push notifications"
        case .settings:      return "Settings (preferences + appearance)"
        case .gdpr:          return "GDPR (data export + delete)"
        case .billing:       return "Billing (StoreKit + entitlements)"
        case .admin:         return "Admin panel"
        }
    }

    var owner: String {
        switch self {
        case .auth, .profile, .gdpr:                 return "auth-team"
        case .rooms, .lifecycle, .deeplinks:         return "navigation-team"
        case .websockets, .sync, .presence:          return "realtime-team"
        case .playback:                              return "playback-team"
        case .chat, .reactions:                      return "chat-team"
        case .friends, .dms:                         return "social-team"
        case .notifications:                         return "platform-team"
        case .settings:                              return "ui-team"
        case .billing:                               return "billing-team"
        case .admin:                                 return "admin-team"
        }
    }

    var testFile: String {
        switch self {
        case .auth:          return "PlinkTests/AuthTests.swift (16 tests via FakeAuthService)"
        case .rooms:         return "PlinkTests/RoomServiceTests.swift (TBD)"
        case .lifecycle:     return "PlinkTests/LifecycleTests.swift (TBD)"
        case .websockets:    return "PlinkTests/RealtimeClientTests.swift (TBD)"
        case .playback:      return "PlinkTests/OrderedSyncControllerTests.swift, PlinkTests/YouTubePlaybackControllerRuntimeTests.swift, PlinkTests/AmbientVideoSamplerTests.swift"
        case .chat:          return "PlinkTests/ChatComposerStateTests.swift"
        case .reactions:     return "PlinkTests/ReactionPaletteTests.swift"
        case .presence:      return "PlinkTests/PresenceTests.swift (TBD)"
        case .sync:          return "PlinkTests/OrderedSyncControllerTests.swift (6) + PlinkTests/ClockSynchronizerTests.swift (11)"
        case .profile:       return "PlinkTests/ProfileTests.swift (TBD)"
        case .friends:       return "PlinkTests/FriendsTests.swift (TBD)"
        case .dms:           return "PlinkTests/DMTests.swift (TBD)"
        case .deeplinks:     return "PlinkTests/DeepLinkTests.swift (TBD)"
        case .notifications: return "PlinkTests/NotificationTests.swift (TBD)"
        case .settings:      return "PlinkTests/SettingsTests.swift (TBD)"
        case .gdpr:          return "PlinkTests/GDPRTests.swift (TBD)"
        case .billing:       return "PlinkTests/StoreManagerTests.swift (TBD)"
        case .admin:         return "PlinkTests/AdminModuleTests.swift (TBD)"
        }
    }

    var telemetry: String {
        switch self {
        case .auth:          return "auth.success, auth.failure, auth.refresh (OSSignpost)"
        case .rooms:         return "room.create, room.join, room.leave (OSSignpost)"
        case .lifecycle:     return "app.background, app.foreground, app.reconnect (OSSignpost)"
        case .websockets:    return "ws.connect, ws.disconnect, ws.reconnect, ws.message_rx (OSSignpost)"
        case .playback:      return "playback.prepare, playback.ready, playback.error, playback.buffering (OSSignpost)"
        case .chat:          return "chat.send, chat.receive, chat.error (OSSignpost)"
        case .reactions:     return "reaction.send, reaction.receive (OSSignpost)"
        case .presence:      return "presence.join, presence.leave, presence.speaking (OSSignpost)"
        case .sync:          return "sync.drift_ms, sync.hard_correction, sync.seq_skipped (OSSignpost)"
        case .profile:       return "profile.update, profile.avatar_upload (OSSignpost)"
        case .friends:       return "friend.add, friend.remove, friend.list (OSSignpost)"
        case .dms:           return "dm.send, dm.receive (OSSignpost)"
        case .deeplinks:     return "deeplink.open, deeplink.invalid (OSSignpost)"
        case .notifications: return "push.received, push.tapped, push.delivery_failed (OSSignpost)"
        case .settings:      return "settings.change (OSSignpost)"
        case .gdpr:          return "gdpr.export_request, gdpr.delete_request (OSSignpost)"
        case .billing:       return "purchase.success, purchase.failure, restore.success, entitlement.refresh (OSSignpost)"
        case .admin:         return "admin.action, admin.audit_write (OSSignpost)"
        }
    }

    var status: RegressionStatus {
        switch self {
        case .playback:  return .green   // OrderedSyncControllerTests (6) + YouTube runtime (10, gated) + Ambient (11)
        case .chat:      return .green   // ChatComposerStateTests (26)
        case .reactions: return .green   // ReactionPaletteTests (23)
        case .auth:      return .green   // PATCH 17: AuthTests (16) via FakeAuthService
        case .sync:      return .green   // PATCH 17: ClockSynchronizerTests (11) + OrderedSyncControllerTests (6)
        case .rooms, .lifecycle, .websockets, .presence, .profile,
             .friends, .dms, .deeplinks, .notifications, .settings, .gdpr,
             .billing, .admin:
            return .red      // Test files TBD
        }
    }
}

enum RegressionStatus: String, Sendable {
    case green   = "green"    // Tests passing, telemetry wired, owner assigned
    case yellow  = "yellow"   // Partial coverage — some tests missing
    case red     = "red"      // Tests missing or failing — blocks release
}

// MARK: - Summary

extension RegressionSystem {
    /// Returns a markdown-formatted table of the full matrix.
    static var markdownTable: String {
        var lines: [String] = []
        lines.append("| System | Owner | Test File | Telemetry | Status |")
        lines.append("|---|---|---|---|---|")
        for system in RegressionSystem.allCases {
            lines.append("| \(system.displayName) | \(system.owner) | \(system.testFile) | \(system.telemetry) | \(system.status.rawValue) |")
        }
        return lines.joined(separator: "\n")
    }

    /// Returns the count of systems in each status.
    static var statusCounts: (green: Int, yellow: Int, red: Int) {
        var green = 0, yellow = 0, red = 0
        for system in RegressionSystem.allCases {
            switch system.status {
            case .green:  green += 1
            case .yellow: yellow += 1
            case .red:    red += 1
            }
        }
        return (green, yellow, red)
    }
}
