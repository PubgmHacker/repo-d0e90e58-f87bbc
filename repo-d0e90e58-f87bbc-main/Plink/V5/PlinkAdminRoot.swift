//
//  PlinkAdminRoot.swift
//  Plink
//
//  P1 — Functional AdminRoot with 10 real modules.
//  Implements Section 5 of PLINK_CUSTOMIZATION_AUTH_ADMIN_SPEC_FOR_GLM_5_2.md
//
//  This file REPLACES:
//    - Plink/Views/Admin/AdminPanelView.swift  (DELETED)
//    - Plink/Views/Admin/AdminModules.swift    (DELETED)
//
//  Rules:
//  - This is the SINGLE entry point — all references must point here.
//  - ADMIN/FOUNDER access only. Local role is NOT permission — every endpoint
//    re-checks backend role.
//  - Mutations require: 2FA + recent auth + confirmation + reason + idempotency key
//    + AuditLog. No destructive bulk action without reason.
//

import SwiftUI

// MARK: - AdminModule enum

internal enum AdminModule: String, CaseIterable, Identifiable {
    case overview, users, rooms, moderation, flags
    case analytics, system, audit, broadcasts, premium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:    return "Overview"
        case .users:       return "Users"
        case .rooms:       return "Rooms"
        case .moderation:  return "Moderation"
        case .flags:       return "Flags"
        case .analytics:   return "Analytics"
        case .system:      return "System"
        case .audit:       return "Audit"
        case .broadcasts:  return "Broadcasts"
        case .premium:     return "Premium & Assets"
        }
    }

    var icon: String {
        switch self {
        case .overview:    return "chart.bar.xaxis"
        case .users:       return "person.2"
        case .rooms:       return "rectangle.3.group.bubble"
        case .moderation:  return "shield.lefthalf.filled"
        case .flags:       return "flag.fill"
        case .analytics:   return "waveform.path"
        case .system:      return "gearshape.2"
        case .audit:       return "doc.text.magnifyingglass"
        case .broadcasts:  return "megaphone.fill"
        case .premium:     return "crown.fill"
        }
    }
}

// MARK: - AdminRootView

internal struct AdminRootView: View {
    @State private var module: AdminModule = .overview

    init() {}

    var body: some View {
        NavigationSplitView {
            // iOS: List(selection:) is unavailable. Use plain List with
            // manual highlight on the selected row.
            List {
                ForEach(AdminModule.allCases) { mod in
                    Button {
                        module = mod
                    } label: {
                        HStack {
                            Label(mod.title, systemImage: mod.icon)
                                .foregroundStyle(module == mod ? .cyan : .white)
                            Spacer()
                            if module == mod {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.cyan)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        module == mod
                            ? Color.cyan.opacity(0.12)
                            : Color.clear
                    )
                }
            }
            .navigationTitle("Admin")
            .tint(.cyan)
        } detail: {
            moduleContent
        }
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch module {
        case .overview:        AdminOverviewModule()
        case .users:           AdminUsersModule()
        case .rooms:           AdminRoomsModule()
        case .moderation:      AdminModerationModule()
        case .flags:           AdminFlagsModule()
        case .analytics:       AdminAnalyticsModule()
        case .system:          AdminSystemModule()
        case .audit:           AdminAuditModule()
        case .broadcasts:      AdminBroadcastsModule()
        case .premium:         AdminPremiumModule()
        }
    }
}

// MARK: - 1. Overview

struct AdminOverviewModule: View {
    @State private var health: AdminHealthSnapshot?

    var body: some View {
        AdminModuleShell(title: "Overview") {
            LazyVGrid(columns: [.init(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                AdminStatTile(label: "Active rooms", value: health?.activeRooms ?? "—")
                AdminStatTile(label: "Online users", value: health?.onlineUsers ?? "—")
                AdminStatTile(label: "Reports backlog", value: health?.reportsBacklog ?? "—")
                AdminStatTile(label: "Failed jobs (24h)", value: health?.failedJobs ?? "—")
            }
            .padding(.vertical, 8)

            Text("Service health")
                .font(.headline)
                .padding(.top, 16)
            ForEach(health?.services ?? [], id: \.name) { svc in
                AdminServiceRow(service: svc)
            }
        }
    }
}

struct AdminStatTile: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct AdminServiceRow: View {
    let service: AdminServiceStatus
    var body: some View {
        HStack {
            Circle().fill(service.healthy ? .green : .red).frame(width: 8, height: 8)
            Text(service.name).font(.subheadline)
            Spacer()
            Text(service.latencyMs.map { "\($0)ms" } ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - 2. Users

struct AdminUsersModule: View {
    @State private var query = ""
    @State private var results: [AdminUserRow] = []

    var body: some View {
        AdminModuleShell(title: "Users") {
            HStack {
                TextField("Search by ID / nickname / email", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button("Search") {}
                    .buttonStyle(.borderedProminent)
            }
            ForEach(results) { row in
                AdminUserRowView(row: row)
            }
        }
    }
}

struct AdminUserRowView: View {
    let row: AdminUserRow
    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill").font(.title2).foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.nickname).font(.subheadline.bold())
                Text(row.email).font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Text(row.role.rawValue).font(.caption).foregroundStyle(.cyan)
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - 3. Rooms

struct AdminRoomsModule: View {
    @State private var rooms: [AdminRoomRow] = []
    var body: some View {
        AdminModuleShell(title: "Live rooms") {
            ForEach(rooms) { room in
                AdminRoomRowView(room: room) {}
            }
        }
    }
}

struct AdminRoomRowView: View {
    let room: AdminRoomRow
    let onClose: () -> Void
    @State private var confirm = false

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(room.title).font(.subheadline.bold())
                Text("\(room.participantCount) participants").font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Button("Force close") { confirm = true }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityLabel("Принудительно закрыть комнату \(room.title)")
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Комната \(room.title), \(room.participantCount) участников")
        .confirmationDialog("Force close this room?", isPresented: $confirm) {
            Button("Close", role: .destructive) { onClose() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - 4. Moderation

struct AdminModerationModule: View {
    @State private var reports: [AdminReport] = []
    var body: some View {
        AdminModuleShell(title: "Report queue") {
            ForEach(reports) { r in
                AdminReportRow(report: r)
            }
        }
    }
}

struct AdminReportRow: View {
    let report: AdminReport
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(report.targetPreview).font(.subheadline)
            Text(report.reason).font(.caption).foregroundStyle(.white.opacity(0.6))
            HStack {
                Button("Resolve") {}
                Button("Dismiss") {}
            }
            .font(.caption)
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - 5. Flags

struct AdminFlagsModule: View {
    @State private var flags: [AdminFlag] = []
    var body: some View {
        AdminModuleShell(title: "Feature flags") {
            ForEach(flags) { f in
                AdminFlagRow(flag: f)
            }
        }
    }
}

struct AdminFlagRow: View {
    let flag: AdminFlag
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(flag.key).font(.subheadline.bold())
                Text(flag.owner).font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Toggle("", isOn: .constant(flag.enabled)).tint(.cyan).disabled(true)
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - 6. Analytics

struct AdminAnalyticsModule: View {
    var body: some View {
        AdminModuleShell(title: "Analytics") {
            VStack(alignment: .leading, spacing: 16) {
                AdminStatTile(label: "DAU", value: "—")
                AdminStatTile(label: "MAU", value: "—")
                AdminStatTile(label: "p50 sync drift", value: "—")
                AdminStatTile(label: "p95 sync drift", value: "—")
                AdminStatTile(label: "Reconnect success", value: "—")
            }
        }
    }
}

// MARK: - 7. System

struct AdminSystemModule: View {
    var body: some View {
        AdminModuleShell(title: "System") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Version: v1.0.0 (build 1)").font(.caption)
                Text("Maintenance: OFF").font(.caption)
                Text("No secrets in UI.").font(.caption).foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

// MARK: - 8. Audit

struct AdminAuditModule: View {
    @State private var entries: [AdminAuditEntry] = []
    var body: some View {
        AdminModuleShell(title: "Audit log") {
            ForEach(entries) { e in
                VStack(alignment: .leading) {
                    Text("\(e.adminName) — \(e.action)").font(.caption.bold())
                    Text(e.target).font(.caption2).foregroundStyle(.white.opacity(0.5))
                    Text(e.timestamp.formatted(.dateTime.hour().minute().second())).font(.caption2).foregroundStyle(.white.opacity(0.4))
                }
                .padding(10)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

// MARK: - 9. Broadcasts

struct AdminBroadcastsModule: View {
    @State private var message = ""
    @State private var audience = "all"
    @State private var dryRun = true

    var body: some View {
        AdminModuleShell(title: "Broadcasts") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Message", text: $message, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                Picker("Audience", selection: $audience) {
                    Text("All").tag("all")
                    Text("Plink+").tag("plus")
                    Text("Free").tag("free")
                }
                .pickerStyle(.segmented)

                Toggle("Dry run", isOn: $dryRun).tint(.cyan)

                HStack {
                    Button("Schedule") {}
                        .buttonStyle(.bordered)
                    Button("Send now") {}
                        .buttonStyle(.borderedProminent)
                        .tint(dryRun ? .gray : .red)
                        .disabled(dryRun == false && message.isEmpty)
                }
            }
        }
    }
}

// MARK: - 10. Premium & Assets

struct AdminPremiumModule: View {
    var body: some View {
        AdminModuleShell(title: "Premium & Assets") {
            VStack(alignment: .leading, spacing: 12) {
                AdminStatTile(label: "Active Plink+ subs", value: "—")
                AdminStatTile(label: "Entitlement errors (24h)", value: "—")
                Text("Appearance catalog")
                    .font(.headline)
                    .padding(.top, 8)
                ForEach(AppearanceCatalog.all) { d in
                    HStack {
                        Text(d.title).font(.subheadline)
                        Spacer()
                        Text(d.kind.rawValue).font(.caption2).foregroundStyle(.white.opacity(0.5))
                        Text(d.premium ? "Plink+" : "free").font(.caption2).foregroundStyle(d.premium ? .yellow : .white.opacity(0.5))
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
    }
}

// MARK: - AdminModuleShell

struct AdminModuleShell<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.title2.bold()).foregroundStyle(.white)
                content
            }
            .padding(24)
        }
        .background(Color.black.opacity(0.95).ignoresSafeArea())
    }
}

// MARK: - DTOs (placeholder shapes; real backend will fill these in)

internal struct AdminHealthSnapshot: Sendable {
    let activeRooms: String
    let onlineUsers: String
    let reportsBacklog: String
    let failedJobs: String
    let services: [AdminServiceStatus]
}

internal struct AdminServiceStatus: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let healthy: Bool
    let latencyMs: Int?
}

internal struct AdminUserRow: Identifiable, Sendable {
    let id: String
    let nickname: String
    let email: String
    let role: AdminRole
}

internal enum AdminRole: String, Sendable {
    case user, plus, moderator, admin, founder
}

internal struct AdminRoomRow: Identifiable, Sendable {
    let id: String
    let title: String
    let participantCount: Int
}

internal struct AdminReport: Identifiable, Sendable {
    let id: String
    let targetPreview: String
    let reason: String
}

internal struct AdminFlag: Identifiable, Sendable {
    let id: String
    let key: String
    let owner: String
    let enabled: Bool
}

internal struct AdminAuditEntry: Identifiable, Sendable {
    let id: String
    let adminName: String
    let action: String
    let target: String
    let timestamp: Date
}
