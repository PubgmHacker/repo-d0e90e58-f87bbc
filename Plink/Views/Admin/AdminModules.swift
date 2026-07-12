// Plink/Views/Admin/AdminModules.swift — PATCH 09: Admin module scaffolding
//
// GLM-5.2 master implementation patch — Commit Group 11.
//
// Defines the 10 admin modules per PATCH 09 spec. Each module is a
// tab in the admin panel with its own view. This file provides:
//   - AdminModule enum (10 cases, all CaseIterable)
//   - AdminModuleView switch view that routes to each module's view
//   - Stub views for modules not yet implemented
//
// Existing AdminPanelView.swift uses AdminTab (3 cases: users, rooms,
// messages). This file introduces AdminModule (10 cases) as the
// authoritative enum. AdminPanelView will be migrated to AdminModule
// in a follow-up commit — for now both coexist so existing tabs keep
// working while new ones are wired up.
//
// PATCH 09 spec modules:
//   1. users        — user list, search, ban/unban, role assignment
//   2. rooms        — room list, force-close, transfer host
//   3. moderation   — reported messages, bulk delete, mute users
//   4. flags        — flagged content queue (auto + user reports)
//   5. analytics    — DAU/MAU, room count, peak concurrency
//   6. system       — health, version, feature flags, maintenance mode
//   7. audit        — AuditLog search by admin/action/target/date
//   8. broadcasts   — push notification composer + history
//   9. premium      — subscription metrics, refund grants, comp codes
//  10. blocklists   — global blocklist (IP, email domain, user agent)
//
// Authorization (per spec):
//   - All authorization is backend-side. iOS only renders the UI.
//   - Backend checks ADMIN/FOUNDER role + 2FA + recent auth on every
//     /api/admin/* request.
//   - Every mutation writes an AuditLog entry (backend-side).
//   - iOS never trusts local role state for admin actions — every
//     action calls backend, backend rejects if unauthorized.

import SwiftUI

// MARK: - AdminModule enum

enum AdminModule: String, CaseIterable, Identifiable {
    case users
    case rooms
    case moderation
    case flags
    case analytics
    case system
    case audit
    case broadcasts
    case premium
    case blocklists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .users:        return "Users"
        case .rooms:        return "Rooms"
        case .moderation:   return "Moderation"
        case .flags:        return "Flags"
        case .analytics:    return "Analytics"
        case .system:       return "System"
        case .audit:        return "Audit Log"
        case .broadcasts:   return "Broadcasts"
        case .premium:      return "Premium"
        case .blocklists:   return "Blocklists"
        }
    }

    var icon: String {
        switch self {
        case .users:        return "person.2.fill"
        case .rooms:        return "rectangle.stack.fill"
        case .moderation:   return "shield.lefthalf.filled"
        case .flags:        return "flag.fill"
        case .analytics:    return "chart.bar.fill"
        case .system:       return "gearshape.fill"
        case .audit:        return "doc.text.magnifyingglass"
        case .broadcasts:   return "megaphone.fill"
        case .premium:      return "star.circle.fill"
        case .blocklists:   return "hand.raised.fill"
        }
    }

    /// Backend route prefix for this module.
    var apiPrefix: String {
        "/api/admin/\(rawValue)"
    }
}

// MARK: - Module router

/// Routes to the appropriate module view. Used by AdminPanelView's
/// tab content area.
struct AdminModuleView: View {
    let module: AdminModule

    var body: some View {
        switch module {
        case .users:        AdminUsersModuleView()
        case .rooms:        AdminRoomsModuleView()
        case .moderation:   AdminModerationModuleView()
        case .flags:        AdminFlagsModuleView()
        case .analytics:    AdminAnalyticsModuleView()
        case .system:       AdminSystemModuleView()
        case .audit:        AdminAuditModuleView()
        case .broadcasts:   AdminBroadcastsModuleView()
        case .premium:      AdminPremiumModuleView()
        case .blocklists:   AdminBlocklistsModuleView()
        }
    }
}

// MARK: - Stub module views
//
// Each stub shows the module title, a brief description, and a
// "Not yet implemented" notice. The actual API calls + tables will be
// implemented in follow-up commits per module.

struct AdminUsersModuleView: View {
    var body: some View {
        AdminModulePlaceholder(
            module: .users,
            description: "User list, search, ban/unban, role assignment. Backend: GET /api/admin/users, POST /api/admin/users/:id/ban, POST /api/admin/users/:id/role."
        )
    }
}

struct AdminRoomsModuleView: View {
    var body: some View {
        AdminModulePlaceholder(
            module: .rooms,
            description: "Room list, force-close, transfer host. Backend: GET /api/admin/rooms, POST /api/admin/rooms/:id/close, POST /api/admin/rooms/:id/transfer."
        )
    }
}

struct AdminModerationModuleView: View {
    var body: some View {
        AdminModulePlaceholder(
            module: .moderation,
            description: "Reported messages, bulk delete, mute users. Backend: GET /api/admin/moderation/queue, POST /api/admin/moderation/messages/:id/delete, POST /api/admin/moderation/users/:id/mute."
        )
    }
}

struct AdminFlagsModuleView: View {
    var body: some View {
        AdminModulePlaceholder(
            module: .flags,
            description: "Flagged content queue (auto + user reports). Backend: GET /api/admin/flags, POST /api/admin/flags/:id/resolve, POST /api/admin/flags/:id/dismiss."
        )
    }
}

struct AdminAnalyticsModuleView: View {
    var body: some View {
        AdminModulePlaceholder(
            module: .analytics,
            description: "DAU/MAU, room count, peak concurrency. Backend: GET /api/admin/analytics/overview, GET /api/admin/analytics/timeseries."
        )
    }
}

struct AdminSystemModuleView: View {
    var body: some View {
        AdminModulePlaceholder(
            module: .system,
            description: "Health, version, feature flags, maintenance mode. Backend: GET /api/admin/system/health, GET /api/admin/system/flags, POST /api/admin/system/maintenance."
        )
    }
}

struct AdminAuditModuleView: View {
    var body: some View {
        AdminModulePlaceholder(
            module: .audit,
            description: "AuditLog search by admin/action/target/date. Backend: GET /api/admin/audit?adminId=&action=&targetId=&from=&to=."
        )
    }
}

struct AdminBroadcastsModuleView: View {
    var body: some View {
        AdminModulePlaceholder(
            module: .broadcasts,
            description: "Push notification composer + history. Backend: POST /api/admin/broadcasts/send, GET /api/admin/broadcasts/history."
        )
    }
}

struct AdminPremiumModuleView: View {
    var body: some View {
        AdminModulePlaceholder(
            module: .premium,
            description: "Subscription metrics, refund grants, comp codes. Backend: GET /api/admin/premium/metrics, POST /api/admin/premium/refund, POST /api/admin/premium/comp."
        )
    }
}

struct AdminBlocklistsModuleView: View {
    var body: some View {
        AdminModulePlaceholder(
            module: .blocklists,
            description: "Global blocklist (IP, email domain, user agent). Backend: GET /api/admin/blocklists, POST /api/admin/blocklists/add, DELETE /api/admin/blocklists/:id."
        )
    }
}

// MARK: - Placeholder

struct AdminModulePlaceholder: View {
    let module: AdminModule
    let description: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: module.icon)
                .font(.system(size: 48))
                .foregroundStyle(Cinema2026.secondary)

            Text(module.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Cinema2026.text)

            Text(description)
                .font(.system(size: 14))
                .foregroundStyle(Cinema2026.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text("Not yet implemented")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Cinema2026.amber)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Cinema2026.amber.opacity(0.12), in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
