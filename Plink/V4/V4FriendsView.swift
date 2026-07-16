// Plink/V4/V4FriendsView.swift — segmented: Чаты | Заявки | Недавние

import SwiftUI
import PhotosUI
import UIKit
import Foundation

struct V4FriendsView: View {
    let theme: V4Theme
    var body: some View {
        ScrollView(showsIndicators:false) {
            VStack(spacing:0) {
                HStack(alignment:.top) { V4Heading(eyebrow:"ВМЕСТЕ ЛУЧШЕ",title:"Друзья"); Spacer(); V4RoundButton(symbol:"＋") }
                    .padding(.horizontal,18).padding(.top,10).padding(.bottom,16)
            }.padding(.bottom,92)
        }.foregroundStyle(V4.ink)
    }
}

// MARK: - Segment

private enum FriendsSegment: String, CaseIterable, Identifiable {
    case chats = "Чаты"
    case requests = "Заявки"
    case recent = "Недавние"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chats: return "bubble.left.and.bubble.right.fill"
        case .requests: return "person.badge.clock.fill"
        case .recent: return "clock.arrow.circlepath"
        }
    }
}

// MARK: - Live friends (server-synced, tabbed)

struct V4FriendsViewLive: View {
    let theme: V4Theme
    var store: V4FriendsStore?
    @State private var segment: FriendsSegment = .chats
    @State private var dmFriend: Friend?
    @State private var profileFriend: Friend?
    @State private var showCreateRoom = false
    @State private var watchWithFriend: Friend?
    @State private var showAddFriend = false
    @State private var toast: String?
    @State private var recentRooms: [Room] = []
    @State private var recentLoading = false
    @State private var roomToOpen: Room?

    private var requestBadge: Int { store?.requests.count ?? 0 }

    var body: some View {
        // NO NavigationStack here — it paints an opaque UIKit chrome that
        // covers PlinkApprovedV4Root's living / live theme background.
        // Home / Rooms / AI / Profile are also plain ScrollViews for this reason.
        // DM / profile / add-friend open as sheets instead.
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                V4Heading(
                    eyebrow: "ВМЕСТЕ",
                    title: segmentTitle
                )
                Spacer()
                if segment == .chats || segment == .requests {
                    Button {
                        HapticManager.impact(.light)
                        showAddFriend = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(V4.accent)
                            .frame(width: 40, height: 40)
                            .background(V4.surface.opacity(0.55))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(V4.line))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Добавить друга")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 12)

            segmentPicker
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                Group {
                    switch segment {
                    case .chats:
                        chatsSection
                    case .requests:
                        requestsSection
                    case .recent:
                        recentSection
                    }
                }
                .padding(.bottom, 100)
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                await store?.load()
                if segment == .recent { await loadRecentRooms() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(V4.ink)
        .background(Color.clear) // must stay clear so root theme shows through
        .sheet(item: $dmFriend) { friend in
            NavigationStack {
                DMChatView(friend: friend)
                    .environmentObject(DMChatService(api: APIClient.shared))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Закрыть") { dmFriend = nil }
                        }
                    }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $profileFriend) { friend in
            NavigationStack {
                FriendProfileView(userId: friend.id, usernameHint: friend.username) {
                    watchWithFriend = friend
                    profileFriend = nil
                    showCreateRoom = true
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Закрыть") { profileFriend = nil }
                    }
                }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showCreateRoom) {
            RoomCreationView { _ in showCreateRoom = false }
                .environmentObject(APIClient.shared)
        }
        .sheet(isPresented: $showAddFriend) {
            if let store {
                AddFriendSheet(store: store) { message in
                    toast = message
                    Task { await store.load() }
                    if message.lowercased().contains("заявк") {
                        withAnimation { segment = .requests }
                    }
                }
            } else {
                Text("Загрузка…").padding()
            }
        }
        .fullScreenCover(item: $roomToOpen) { room in
            WatchRoomContainer(room: room)
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(V4.surface.opacity(0.95), in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 2_200_000_000)
                            withAnimation { self.toast = nil }
                        }
                    }
            }
        }
        .task {
            await store?.load()
        }
        .onChange(of: segment) { _, new in
            if new == .recent {
                Task { await loadRecentRooms() }
            }
        }
    }

    private var segmentTitle: String {
        switch segment {
        case .chats: return "Чаты"
        case .requests: return "Заявки"
        case .recent: return "Недавние"
        }
    }

    // MARK: - Segment picker

    private var segmentPicker: some View {
        HStack(spacing: 6) {
            ForEach(FriendsSegment.allCases) { seg in
                let selected = segment == seg
                let badge = seg == .requests ? requestBadge : 0
                Button {
                    HapticManager.selection()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        segment = seg
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: seg.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(seg.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(selected ? V4.accentInk : .white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(selected ? Color.white.opacity(0.9) : V4.accent.opacity(0.9), in: Capsule())
                        }
                    }
                    .foregroundStyle(selected ? V4.accentInk : V4.ink.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        selected
                            ? AnyShapeStyle(V4.accent.opacity(0.95))
                            : AnyShapeStyle(V4.surface.opacity(0.42))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(selected ? Color.clear : V4.line.opacity(0.7), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(seg.rawValue)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: - Чаты

    @ViewBuilder
    private var chatsSection: some View {
        if let s = store {
            switch s.state {
            case .loading:
                ProgressView().tint(V4.accent).padding(.top, 50)
            case .failed(let err):
                emptyBlock(icon: "wifi.exclamationmark", title: "Ошибка", subtitle: err)
            case .idle:
                Color.clear.frame(height: 40)
            case .loaded, .empty:
                if s.friends.isEmpty {
                    emptyBlock(
                        icon: "bubble.left.and.bubble.right",
                        title: "Пока нет чатов",
                        subtitle: "Добавь друга — здесь появятся личные сообщения",
                        cta: "Добавить друга"
                    ) { showAddFriend = true }
                } else {
                    Text("Личные сообщения")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(V4.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 19)
                        .padding(.bottom, 6)

                    VStack(spacing: 0) {
                        ForEach(s.friends) { friend in
                            friendChatRow(friend)
                        }
                    }
                    .padding(.horizontal, 19)
                }
            }
        } else {
            ProgressView().tint(V4.accent).padding(.top, 50)
        }
    }

    // MARK: - Заявки

    @ViewBuilder
    private var requestsSection: some View {
        if let s = store {
            if s.requests.isEmpty && s.outgoing.isEmpty {
                emptyBlock(
                    icon: "person.badge.clock",
                    title: "Нет заявок",
                    subtitle: "Входящие и отправленные запросы на дружбу появятся здесь",
                    cta: "Найти друга"
                ) { showAddFriend = true }
            } else {
                if !s.requests.isEmpty {
                    Text("ВХОДЯЩИЕ")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(V4.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 19)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(s.requests) { req in
                            incomingRow(req, store: s)
                        }
                    }
                    .padding(.horizontal, 19)
                    .padding(.bottom, 20)
                }

                if !s.outgoing.isEmpty {
                    Text("ОТПРАВЛЕННЫЕ")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(V4.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 19)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(s.outgoing) { req in
                            HStack(spacing: 11) {
                                V4Avatar(letter: String(req.toUser.username.prefix(1)), theme: theme, size: 39)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(req.toUser.username)
                                        .font(.system(size: 13.6, weight: .bold))
                                    Text("Ожидает ответа")
                                        .font(.system(size: 11.52))
                                        .foregroundStyle(V4.muted)
                                }
                                Spacer()
                                Text("Ожидание")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(V4.amber)
                                    .padding(.horizontal, 10)
                                    .frame(height: 30)
                                    .background(V4.amber.opacity(0.12), in: Capsule())
                            }
                            .frame(minHeight: 56)
                            .overlay(alignment: .bottom) { Rectangle().fill(V4.line).frame(height: 1) }
                        }
                    }
                    .padding(.horizontal, 19)
                }
            }
        } else {
            ProgressView().tint(V4.accent).padding(.top, 50)
        }
    }

    // MARK: - Недавние

    @ViewBuilder
    private var recentSection: some View {
        if recentLoading && recentRooms.isEmpty {
            ProgressView().tint(V4.accent).padding(.top, 50)
        } else if recentRooms.isEmpty {
            emptyBlock(
                icon: "clock.arrow.circlepath",
                title: "Нет недавних комнат",
                subtitle: "Комнаты, где ты был хостом, появятся здесь",
                cta: "Создать комнату"
            ) {
                showCreateRoom = true
            }
        } else {
            Text("Твои комнаты")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(V4.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 19)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(recentRooms) { room in
                    Button {
                        HapticManager.impact(.light)
                        roomToOpen = room
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(V4.surface)
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Image(systemName: "play.rectangle.fill")
                                        .foregroundStyle(V4.accent)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(room.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(V4.ink)
                                    .lineLimit(1)
                                Text("Код \(room.code) · \(room.participantCount) чел.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(V4.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(V4.muted)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) { Rectangle().fill(V4.line).frame(height: 1) }
                }
            }
            .padding(.horizontal, 19)
        }
    }

    private func loadRecentRooms() async {
        recentLoading = true
        defer { recentLoading = false }
        do {
            let rooms = try await RoomService(api: APIClient.shared).fetchMyRooms()
            recentRooms = rooms
        } catch {
            // keep previous list
        }
    }

    // MARK: - Shared UI

    private func emptyBlock(
        icon: String,
        title: String,
        subtitle: String,
        cta: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(V4.accent)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(V4.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if let cta, let action {
                Button(action: action) {
                    Text(cta)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(V4.accentInk)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(V4.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private func friendChatRow(_ friend: Friend) -> some View {
        HStack(spacing: 11) {
            Button { profileFriend = friend } label: {
                V4Avatar(letter: String(friend.username.prefix(1)), theme: theme, size: 42)
            }
            .buttonStyle(.plain)

            Button { dmFriend = friend } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.username)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(V4.ink)
                    Text(friend.isOnline ? "В сети" : "Не в сети")
                        .font(.system(size: 12))
                        .foregroundStyle(friend.isOnline ? V4.accent : V4.muted)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button { dmFriend = friend } label: {
                Image(systemName: "message.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(V4.ink)
                    .frame(width: 38, height: 38)
                    .background(V4.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(V4.line))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Чат")

            Button {
                HapticManager.impact(.light)
                watchWithFriend = friend
                showCreateRoom = true
            } label: {
                Text("Смотреть")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(V4.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(V4.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(V4.line))
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) { Rectangle().fill(V4.line).frame(height: 1) }
    }

    private func incomingRow(_ req: FriendRequest, store: V4FriendsStore) -> some View {
        HStack(spacing: 11) {
            V4Avatar(letter: String(req.fromUser.username.prefix(1)), theme: theme, size: 39)
            VStack(alignment: .leading, spacing: 2) {
                Text(req.fromUser.username)
                    .font(.system(size: 13.6, weight: .bold))
                Text("хочет добавить вас в друзья")
                    .font(.system(size: 11.52))
                    .foregroundStyle(V4.muted)
            }
            Spacer()
            Button {
                HapticManager.impact(.medium)
                Task {
                    await store.accept(req)
                    toast = "\(req.fromUser.username) в друзьях"
                    withAnimation { segment = .chats }
                }
            } label: {
                Text("Принять")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(V4.accentInk)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(V4.accent, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Button {
                HapticManager.impact(.light)
                Task {
                    await store.decline(req)
                    toast = "Заявка отклонена"
                }
            } label: {
                Text("Нет")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(V4.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(V4.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(V4.line))
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) { Rectangle().fill(V4.line).frame(height: 1) }
    }
}

// MARK: - Add Friend Sheet

private struct AddFriendSheet: View {
    let store: V4FriendsStore
    var onDone: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var directUsername = ""
    @State private var isSending = false
    @State private var localError: String?
    @State private var searchTask: Task<Void, Never>?

    private var manager: FriendManager { store.friendManager }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Добавить по @username")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(V4.muted)

                    HStack(spacing: 10) {
                        TextField("@ник друга", text: $directUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(V4.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(V4.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(V4.line))

                        Button {
                            Task { await sendByUsername() }
                        } label: {
                            if isSending {
                                ProgressView().tint(V4.accentInk).frame(width: 48, height: 48)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(V4.accentInk)
                                    .frame(width: 48, height: 48)
                                    .background(V4.accent, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isSending || directUsername.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    Text("Друг получит заявку во вкладке «Заявки».")
                        .font(.system(size: 12))
                        .foregroundStyle(V4.muted)
                }
                .padding(18)

                Divider().overlay(V4.line)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Или найти")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(V4.muted)
                        .padding(.horizontal, 18)
                        .padding(.top, 14)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(V4.muted)
                        TextField("Поиск по нику…", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(V4.ink)
                            .onChange(of: query) { _, new in
                                searchTask?.cancel()
                                searchTask = Task {
                                    try? await Task.sleep(nanoseconds: 350_000_000)
                                    guard !Task.isCancelled else { return }
                                    await manager.searchUsers(query: new)
                                }
                            }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(V4.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(V4.line))
                    .padding(.horizontal, 18)

                    if let localError {
                        Text(localError)
                            .font(.caption)
                            .foregroundStyle(V4.danger)
                            .padding(.horizontal, 18)
                    }

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(manager.searchResults) { user in
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(V4.accent.opacity(0.25))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Text(String(user.username.prefix(1)).uppercased())
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundStyle(.white)
                                        )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.username)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(V4.ink)
                                        Text(user.isOnline ? "в сети" : "не в сети")
                                            .font(.system(size: 12))
                                            .foregroundStyle(V4.muted)
                                    }
                                    Spacer()
                                    if manager.isFriend(user.id) {
                                        Text("Друг").font(.system(size: 12, weight: .semibold)).foregroundStyle(V4.muted)
                                    } else if manager.hasOutgoingRequest(to: user.id) {
                                        Text("Отправлено").font(.system(size: 12, weight: .semibold)).foregroundStyle(V4.amber)
                                    } else {
                                        Button {
                                            Task { await sendToUser(user) }
                                        } label: {
                                            Text("Добавить")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(V4.accentInk)
                                                .padding(.horizontal, 12)
                                                .frame(height: 34)
                                                .background(V4.accent, in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 70)
                                }
                            }
                            if manager.searchResults.isEmpty && !query.isEmpty && !manager.isLoading {
                                Text("Никого не нашли")
                                    .font(.subheadline)
                                    .foregroundStyle(V4.muted)
                                    .padding(.top, 24)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                }
            }
            .background(V4.canvas.ignoresSafeArea())
            .navigationTitle("Добавить друга")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func sendByUsername() async {
        isSending = true
        localError = nil
        defer { isSending = false }
        let ok = await manager.sendRequestByUsername(directUsername)
        if ok {
            onDone(manager.lastSuccessMessage ?? "Заявка отправлена")
            dismiss()
        } else {
            localError = manager.errorMessage ?? "Не удалось отправить"
        }
    }

    private func sendToUser(_ user: UserPreview) async {
        isSending = true
        localError = nil
        defer { isSending = false }
        let ok = await manager.sendRequest(to: user.id, username: user.username)
        if ok {
            onDone(manager.lastSuccessMessage ?? "Заявка отправлена")
            await manager.searchUsers(query: query)
        } else {
            localError = manager.errorMessage ?? "Не удалось отправить"
        }
    }
}


