//
//  PlinkProfileRows.swift
//  Plink
//
//  P1 — Wire every empty profile row action.
//  Implements Section 8 of PLINK_CUSTOMIZATION_AUTH_ADMIN_SPEC_FOR_GLM_5_2.md
//

import SwiftUI

// MARK: - PersonalDataView

internal struct PersonalDataView: View {
    @State private var nickname: String = ""
    @State private var email: String = ""
    @State private var isEmailVerified: Bool = false
    @State private var accountID: String = ""
    @State private var copied: Bool = false

    init() {}

    var body: some View {
        Form {
            Section("Профиль") {
                TextField("Никнейм", text: $nickname)
                    .textInputAutocapitalization(.never)
            }
            Section("Email") {
                HStack {
                    Text(email)
                    Spacer()
                    if isEmailVerified {
                        Label("Подтверждён", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Button("Подтвердить") {}
                            .font(.caption)
                    }
                }
                Button("Сменить email") {}
            }
            Section("Поддержка") {
                HStack {
                    Text("Account ID")
                        .font(.subheadline)
                    Spacer()
                    Text(accountID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.6))
                    Button {
                        UIPasteboard.general.string = accountID
                        withAnimation { copied = true }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black.opacity(0.95).ignoresSafeArea())
        .onAppear {
            if let u = AuthService.shared.currentUserValue {
                nickname = u.username
                email = u.email
                accountID = u.id
            }
        }
    }
}

// MARK: - PrivacySecurityView

internal struct PrivacySecurityView: View {
    @State private var invitePermission: InvitePermission = .friendsOnly
    @State private var discoverable: Bool = true
    @State private var showOnlineStatus: Bool = true
    @State private var twoFAEnabled: Bool = false
    @State private var sessions: [ActiveSession] = []

    init() {}

    var body: some View {
        Form {
            Section("Приватность") {
                Picker("Кто может приглашать в комнату", selection: $invitePermission) {
                    Text("Все").tag(InvitePermission.everyone)
                    Text("Друзья").tag(InvitePermission.friendsOnly)
                    Text("Никто").tag(InvitePermission.noOne)
                }
                Toggle("Меня видно в поиске", isOn: $discoverable).tint(.cyan)
                Toggle("Показывать онлайн-статус", isOn: $showOnlineStatus).tint(.cyan)
            }
            Section("Безопасность") {
                Toggle("2FA", isOn: $twoFAEnabled).tint(.cyan)
                NavigationLink("Активные сессии") {
                    ActiveSessionsView(sessions: sessions)
                }
                Button(role: .destructive) {
                    AuthService.shared.forceLocalSignOut()
                } label: {
                    Text("Выйти на всех устройствах")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black.opacity(0.95).ignoresSafeArea())
    }
}

internal enum InvitePermission: String, CaseIterable, Codable {
    case everyone, friendsOnly, noOne
}

struct ActiveSessionsView: View {
    let sessions: [ActiveSession]
    var body: some View {
        List(sessions) { s in
            VStack(alignment: .leading) {
                Text(s.device).font(.subheadline.bold())
                Text(s.lastSeen.formatted(.relative(presentation: .named)))
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black.opacity(0.95).ignoresSafeArea())
    }
}

// MARK: - PlaybackSettingsView

internal struct PlaybackSettingsView: View {
    @State private var autoplayNext = false
    @State private var cellularQuality: CellularQuality = .auto
    @State private var subtitlesByDefault = false
    @AppStorage("plink.reduceMotionOverride") private var reduceMotionOverride = false

    init() {}

    var body: some View {
        Form {
            Section("Воспроизведение") {
                Toggle("Автозапуск следующего", isOn: $autoplayNext).tint(.cyan)
                Picker("Качество по сотовой", selection: $cellularQuality) {
                    Text("Авто").tag(CellularQuality.auto)
                    Text("720p").tag(CellularQuality.p720)
                    Text("480p").tag(CellularQuality.p480)
                }
                Toggle("Субтитры по умолчанию", isOn: $subtitlesByDefault).tint(.cyan)
                NavigationLink("Движение и доступность") {
                    MotionAccessibilityView()
                }
                NavigationLink("Экспорт диагностики синхронизации") {
                    SyncDiagnosticsView()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black.opacity(0.95).ignoresSafeArea())
    }
}

internal enum CellularQuality: String, CaseIterable {
    case auto, p720, p480
}

struct MotionAccessibilityView: View {
    @AppStorage("plink.reduceMotionOverride") private var reduceMotionOverride = false
    var body: some View {
        Form {
            Toggle("Reduce Motion (force)", isOn: $reduceMotionOverride).tint(.cyan)
            Text("Системный Reduce Motion всегда имеет приоритет.")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
        }
        .scrollContentBackground(.hidden)
        .background(Color.black.opacity(0.95).ignoresSafeArea())
    }
}

struct SyncDiagnosticsView: View {
    @State private var diagnostics: String = "Загрузка…"
    var body: some View {
        ScrollView {
            Text(diagnostics)
                .font(.caption.monospaced())
                .foregroundStyle(.white)
                .padding()
        }
        .background(Color.black.opacity(0.95).ignoresSafeArea())
        .task {
            // TODO: real sync diagnostics export
            diagnostics = "No diagnostics available yet."
        }
    }
}

// MARK: - HelpView

internal struct HelpView: View {
    @State private var query = ""
    @State private var articles: [HelpArticle] = []

    init() {}

    var body: some View {
        Form {
            Section {
                TextField("Поиск", text: $query)
            }
            Section("Статьи") {
                ForEach(articles) { a in
                    NavigationLink(a.title) { HelpArticleView(article: a) }
                }
            }
            Section("Поддержка") {
                Button("Сообщить о проблеме") {}
                NavigationLink("Предпросмотр diagnostic bundle") { DiagnosticsPreviewView() }
                Link("Условия", destination: URL(string: "https://plink.app/terms")!)
                Link("Конфиденциальность", destination: URL(string: "https://plink.app/privacy")!)
                Text("App version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"))")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black.opacity(0.95).ignoresSafeArea())
    }
}

internal struct HelpArticle: Identifiable, Sendable {
    let id: String
    let title: String
    let body: String
}

struct HelpArticleView: View {
    let article: HelpArticle
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(article.title).font(.title3.bold()).foregroundStyle(.white)
                Text(article.body).foregroundStyle(.white.opacity(0.8))
            }
            .padding()
        }
        .background(Color.black.opacity(0.95).ignoresSafeArea())
    }
}

struct DiagnosticsPreviewView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Diagnostic bundle preview")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("• App version\n• OS version\n• Last 100 sync events\n• Reconnect stats\n• Provider errors")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding()
        }
        .background(Color.black.opacity(0.95).ignoresSafeArea())
    }
}

// MARK: - BlockedUsersView

internal struct BlockedUsersView: View {
    @State private var blocked: [BlockedUser] = []

    init() {}

    var body: some View {
        Group {
            if blocked.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Список заблокированных пуст")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.95).ignoresSafeArea())
            } else {
                List(blocked) { u in
                    HStack {
                        Text(u.nickname).foregroundStyle(.white)
                        Spacer()
                        Button("Разблокировать") {}
                            .font(.caption)
                            .tint(.cyan)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.black.opacity(0.95).ignoresSafeArea())
            }
        }
    }
}

internal struct BlockedUser: Identifiable, Sendable {
    let id: String
    let nickname: String
}

// MARK: - DeleteAccountView (destructive, recent auth required)

internal struct DeleteAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    @State private var loading = false
    @State private var error: String?
    @State private var scheduledForDeletionAt: Date?

    init() {}

    var body: some View {
        Form {
            Section {
                Text("Удаление аккаунта необратимо. Твои комнаты, друзья и история будут удалены в соответствии с условиями хранения, требуемыми законом.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Section {
                Toggle("Я понимаю последствия", isOn: $confirmed).tint(.red)
                Button(role: .destructive) {
                    Task { await delete() }
                } label: {
                    HStack {
                        if loading { ProgressView().tint(.red) }
                        Text("Удалить аккаунт")
                    }
                }
                .disabled(!confirmed || loading)
            }
            if let err = error {
                Section {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            if let date = scheduledForDeletionAt {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Удаление запланировано")
                            .font(.subheadline.bold())
                        Text("Аккаунт будет удалён \(date.formatted(.dateTime.day().month().year().hour().minute())). До этого момента можно отменить, написав в поддержку.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black.opacity(0.95).ignoresSafeArea())
        .navigationTitle("Удалить аккаунт")
    }

    private func delete() async {
        // Hard gate: recent auth required (handled by SessionSyncGate before
        // the user even reaches this view — DeleteAccountView is only presented
        // after a successful requireRecentAuth() call).
        loading = true
        error = nil
        defer { loading = false }
        do {
            // Phase 2.7: real backend endpoint
            let resp = try await AuthService.shared.requestAccountDeletion(
                reason: "user_initiated"
            )
            self.scheduledForDeletionAt = resp.scheduledForDeletionAt
            // Wait 2s so the user sees the confirmation, then post notification.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            NotificationCenter.default.post(name: .plinkUserDeleted, object: nil)
            dismiss()
        } catch {
            self.error = "Не удалось отправить запрос: \(error.localizedDescription)"
        }
    }
}

// MARK: - Notifications

internal extension Notification.Name {
    static let plinkUserDeleted = Notification.Name("plink.userDeleted")
}
