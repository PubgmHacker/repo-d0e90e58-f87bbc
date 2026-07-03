import SwiftUI

// MARK: - Admin Panel View
/// Админ-панель: управление пользователями, комнатами, сообщениями.
/// Доступна только для пользователей с ролью ADMIN.
struct AdminPanelView: View {
    @Environment(\.dismiss) private var dismiss
    private let api = APIClient()

    @State private var selectedTab: AdminTab = .users
    @State private var users: [AdminUser] = []
    @State private var rooms: [Room] = []
    @State private var messages: [AdminMessage] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var toastMessage: String?

    enum AdminTab: String, CaseIterable {
        case users, rooms, messages
        var title: String {
            switch self {
            case .users: return "Пользователи"
            case .rooms: return "Комнаты"
            case .messages: return "Сообщения"
            }
        }
        var icon: String {
            switch self {
            case .users: return "person.2.fill"
            case .rooms: return "rectangle.stack.fill"
            case .messages: return "bubble.left.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground(orbColors: [Color(hex: 0xFF3D8B), Color(hex: 0x6EC1E4), Color(hex: 0xE8B339)])

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Админ-панель")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(.raveTextPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.raveTextSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)

                // Tab picker
                HStack(spacing: 8) {
                    ForEach(AdminTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 13))
                                Text(tab.title)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(selectedTab == tab ? .white : .raveTextSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                selectedTab == tab
                                    ? AnyShapeStyle(Color.raveGradient)
                                    : AnyShapeStyle(Color.white.opacity(0.06))
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                // Search
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.raveTextSecondary)
                    TextField("Поиск...", text: $searchText)
                        .foregroundColor(.raveTextPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassCard(cornerRadius: 12, opacity: 0.05)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                // Content
                ScrollView {
                    switch selectedTab {
                    case .users: usersContent
                    case .rooms: roomsContent
                    case .messages: messagesContent
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .task {
            await loadAllData()
        }
        .refreshable { await loadAllData() }
        .overlay(alignment: .top) {
            if let toast = toastMessage {
                Text(toast)
                    .font(.subheadline.bold())
                    .foregroundColor(.raveTextPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassCard(cornerRadius: 14, opacity: 0.08)
                    .padding(.top, 50)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            await MainActor.run { self.toastMessage = nil }
                        }
                    }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Users Tab

    @ViewBuilder
    private var usersContent: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredUsers) { user in
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.raveGradient)
                        Text(user.username.prefix(1).uppercased())
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.username)
                            .font(.subheadline.bold())
                            .foregroundColor(.raveTextPrimary)
                        Text(user.email)
                            .font(.caption2)
                            .foregroundColor(.raveTextSecondary)
                    }

                    Spacer()

                    // Role badge
                    Text(user.role)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(roleColor(user.role))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(roleColor(user.role).opacity(0.15))
                        .clipShape(Capsule())

                    // Ban / Unban
                    Button {
                        Task {
                            if user.role == "BANNED" {
                                await adminAction("users/\(user.id)/unban", method: .post)
                                toastMessage = "Разбанен: \(user.username)"
                            } else {
                                await adminAction("users/\(user.id)/ban", method: .post)
                                toastMessage = "Забанен: \(user.username)"
                            }
                            await loadAllData()
                        }
                    } label: {
                        Image(systemName: user.role == "BANNED" ? "person.badge.checkmark" : "person.badge.xmark")
                            .font(.system(size: 16))
                            .foregroundColor(user.role == "BANNED" ? .raveGreen : .raveDanger)
                            .frame(width: 36, height: 36)
                            .glassCard(cornerRadius: 18, opacity: 0.06)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .glassCard(cornerRadius: 14, opacity: 0.04)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Rooms Tab

    @ViewBuilder
    private var roomsContent: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredRooms) { room in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.raveGradient.opacity(0.3))
                        Image(systemName: "play.rectangle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(room.name)
                            .font(.subheadline.bold())
                            .foregroundColor(.raveTextPrimary)
                            .lineLimit(1)
                        Text("Хост: \(room.hostName) · \(room.participantCount) чел.")
                            .font(.caption2)
                            .foregroundColor(.raveTextSecondary)
                    }

                    Spacer()

                    Button {
                        Task {
                            await adminAction("rooms/\(room.id)", method: .delete)
                            toastMessage = "Комната закрыта: \(room.name)"
                            await loadAllData()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.raveDanger)
                            .frame(width: 36, height: 36)
                            .glassCard(cornerRadius: 18, opacity: 0.06)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .glassCard(cornerRadius: 14, opacity: 0.04)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Messages Tab

    @ViewBuilder
    private var messagesContent: some View {
        if messages.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 36))
                    .foregroundColor(.raveTextTertiary)
                Text("Сообщения не загружены")
                    .font(.subheadline)
                    .foregroundColor(.raveTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            LazyVStack(spacing: 6) {
                ForEach(messages) { msg in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.ravePrimary.opacity(0.15))
                            Text(msg.senderName.prefix(1).uppercased())
                                .font(.caption.bold())
                                .foregroundColor(.ravePrimary)
                        }
                        .frame(width: 30, height: 30)

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(msg.senderName)
                                    .font(.caption.bold())
                                    .foregroundColor(.raveTextPrimary)
                                Text(msg.timeAgo)
                                    .font(.system(size: 10))
                                    .foregroundColor(.raveTextTertiary)
                            }
                            Text(msg.text)
                                .font(.caption)
                                .foregroundColor(.raveTextSecondary)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .glassCard(cornerRadius: 12, opacity: 0.03)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Data Loading

    private func loadAllData() async {
        isLoading = true
        defer { isLoading = false }

        await loadUsers()
        await loadRooms()
    }

    private func loadUsers() async {
        do {
            struct UsersResponse: Decodable {
                let users: [AdminUser]?
            }
            let resp: UsersResponse = try await api.request("admin/users")
            users = resp.users ?? []
        } catch {
            print("[Admin] loadUsers error: \(error.localizedDescription)")
        }
    }

    private func loadRooms() async {
        do {
            let allRooms: [Room] = try await api.request("rooms")
            rooms = allRooms
        } catch {
            print("[Admin] loadRooms error: \(error.localizedDescription)")
        }
    }

    private func adminAction(_ path: String, method: HTTPMethod) async {
        do {
            try await api.requestNoBody("admin/\(path)", method: method)
        } catch {
            toastMessage = "Ошибка: \(error.localizedDescription)"
        }
    }

    // MARK: - Filters

    private var filteredUsers: [AdminUser] {
        if searchText.isEmpty { return users }
        return users.filter {
            $0.username.localizedCaseInsensitiveContains(searchText) ||
            $0.email.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredRooms: [Room] {
        if searchText.isEmpty { return rooms }
        return rooms.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.hostName.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Helpers

    private func roleColor(_ role: String) -> Color {
        switch role.uppercased() {
        case "ADMIN": return .raveWarning
        case "BANNED": return .raveDanger
        case "PREMIUM": return .raveCyan
        default: return .raveGreen
        }
    }
}

// MARK: - Admin Models

struct AdminUser: Identifiable, Decodable {
    let id: String
    let username: String
    let email: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case id, username, email, role
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        email = try c.decode(String.self, forKey: .email)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "USER"
    }
}

struct AdminMessage: Identifiable {
    let id = UUID()
    let senderName: String
    let text: String
    let timeAgo: String
}
