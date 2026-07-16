// Plink/V4/V4FriendsView.swift
// Layout: Чаты + Недавние комнаты as page sections.
// Заявки = header icon (badge) next to «Добавить друга».

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

// MARK: - Live friends

struct V4FriendsViewLive: View {
    let theme: V4Theme
    var store: V4FriendsStore?
    /// When false (other tab), pause polling. Root passes tab == friends.
    var isActive: Bool = true
    @State private var dmFriend: Friend?
    @State private var profileFriend: Friend?
    @State private var showCreateRoom = false
    @State private var watchWithFriend: Friend?
    @State private var showAddFriend = false
    @State private var showRequests = false
    @State private var toast: String?
    @State private var recentRooms: [Room] = []
    @State private var recentLoading = false
    @State private var roomToOpen: Room?
    @Environment(\.scenePhase) private var scenePhase

    private var requestBadge: Int { store?.requests.count ?? 0 }

    var body: some View {
        // No NavigationStack — keep living theme visible
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    chatsBlock
                    recentBlock
                }
                .padding(.bottom, 100)
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                await store?.load()
                await loadRecentRooms()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(V4.ink)
        .background(Color.clear)
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
                    // Delay slightly so toast appears after sheet dismisses
                    Task { @MainActor in
                        await store.load()
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            toast = message
                        }
                    }
                }
            } else {
                Text("Загрузка…").padding()
            }
        }
        .sheet(isPresented: $showRequests) {
            if let store {
                FriendRequestsSheet(theme: theme, store: store) { message in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        toast = message
                    }
                }
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
                    .padding(.top, 12)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 2_400_000_000)
                            withAnimation { self.toast = nil }
                        }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast)
        .task {
            await store?.load()
            await loadRecentRooms()
        }
        // Tabs stay mounted (opacity switch) — re-fetch when this tab is shown
        .onChange(of: isActive) { _, active in
            guard active else { return }
            Task {
                await store?.refreshQuietly()
                await loadRecentRooms()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, isActive else { return }
            Task { await store?.refreshQuietly() }
        }
        // Poll while friends tab is open so accept on other phone appears
        .task(id: isActive) {
            guard isActive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000) // 8s
                guard !Task.isCancelled, isActive else { break }
                await store?.refreshQuietly()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            V4Heading(eyebrow: "ВМЕСТЕ", title: "Друзья")
            Spacer(minLength: 8)

            // Заявки — icon only, badge if incoming
            Button {
                HapticManager.impact(.light)
                showRequests = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: requestBadge > 0 ? "person.badge.clock.fill" : "tray.full")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(requestBadge > 0 ? V4.accent : V4.ink)
                        .frame(width: 40, height: 40)
                        .background(V4.surface.opacity(0.5))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(V4.line.opacity(0.8)))

                    if requestBadge > 0 {
                        Text(requestBadge > 9 ? "9+" : "\(requestBadge)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(V4.accentInk)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(V4.accent, in: Capsule())
                            .offset(x: 4, y: -2)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(requestBadge > 0 ? "Заявки, \(requestBadge)" : "Заявки")

            // Добавить друга
            Button {
                HapticManager.impact(.light)
                showAddFriend = true
            } label: {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(V4.accent)
                    .frame(width: 40, height: 40)
                    .background(V4.surface.opacity(0.5))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(V4.line.opacity(0.8)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Добавить друга")
        }
    }

    // MARK: - Section chrome

    private func sectionHeader(title: String, icon: String, count: Int?, actionTitle: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(V4.accent)
                .frame(width: 28, height: 28)
                .background(V4.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(V4.ink)

            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(V4.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(V4.surface.opacity(0.55), in: Capsule())
                    .overlay(Capsule().stroke(V4.line.opacity(0.6)))
            }

            Spacer()

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(V4.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(V4.surface.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(V4.line.opacity(0.65), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func emptyInside(icon: String, title: String, subtitle: String, cta: String? = nil, action: (() -> Void)? = nil) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(V4.accent.opacity(0.85))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(V4.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            if let cta, let action {
                Button(action: action) {
                    Text(cta)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(V4.accentInk)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(V4.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 12)
    }

    // MARK: - Чаты block

    @ViewBuilder
    private var chatsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Чаты",
                icon: "bubble.left.and.bubble.right.fill",
                count: store?.friends.count,
                actionTitle: "Добавить",
                action: { showAddFriend = true }
            )

            if let s = store {
                switch s.state {
                case .loading:
                    sectionCard {
                        ProgressView().tint(V4.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                    }
                case .failed(let err):
                    sectionCard {
                        emptyInside(icon: "wifi.exclamationmark", title: "Не загрузилось", subtitle: err)
                    }
                case .idle:
                    Color.clear.frame(height: 1)
                case .loaded, .empty:
                    sectionCard {
                        if s.friends.isEmpty {
                            emptyInside(
                                icon: "bubble.left.and.bubble.right",
                                title: "Пока нет чатов",
                                subtitle: "Добавь друга — здесь появятся личные сообщения",
                                cta: "Найти друга"
                            ) { showAddFriend = true }
                        } else {
                            ForEach(s.friends) { friend in
                                friendChatRow(friend)
                            }
                        }
                    }
                }
            } else {
                sectionCard {
                    ProgressView().tint(V4.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                }
            }
        }
    }

    // MARK: - Недавние block

    @ViewBuilder
    private var recentBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Недавние комнаты",
                icon: "clock.arrow.circlepath",
                count: recentRooms.isEmpty ? nil : recentRooms.count,
                actionTitle: "Создать",
                action: { showCreateRoom = true }
            )

            sectionCard {
                if recentLoading && recentRooms.isEmpty {
                    ProgressView().tint(V4.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                } else if recentRooms.isEmpty {
                    emptyInside(
                        icon: "play.rectangle.fill",
                        title: "Нет недавних комнат",
                        subtitle: "Комнаты, где ты был хостом, появятся здесь",
                        cta: "Создать комнату"
                    ) { showCreateRoom = true }
                } else {
                    ForEach(recentRooms) { room in
                        recentRoomRow(room)
                    }
                }
            }
        }
    }

    // MARK: - Rows

    private func friendChatRow(_ friend: Friend) -> some View {
        HStack(spacing: 12) {
            Button { profileFriend = friend } label: {
                V4Avatar(
                    letter: String(friend.username.prefix(1)).uppercased(),
                    theme: theme,
                    size: 44,
                    imageURL: PlinkAvatarURL.resolve(userId: friend.id, stored: friend.avatarURL)
                )
            }
            .buttonStyle(.plain)

            Button { dmFriend = friend } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(friend.username)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(V4.ink)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(friend.isOnline ? Color(red: 0.3, green: 0.9, blue: 0.55) : V4.muted.opacity(0.5))
                            .frame(width: 7, height: 7)
                        Text(friend.isOnline ? "В сети · написать" : "Не в сети · написать")
                            .font(.system(size: 12))
                            .foregroundStyle(V4.muted)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 6)

            Button { dmFriend = friend } label: {
                Image(systemName: "message.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(V4.ink)
                    .frame(width: 38, height: 38)
                    .background(V4.raised.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(V4.line.opacity(0.7)))
            }
            .buttonStyle(.plain)

            Button {
                HapticManager.impact(.light)
                watchWithFriend = friend
                showCreateRoom = true
            } label: {
                Text("Смотреть")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(V4.accentInk)
                    .padding(.horizontal, 11)
                    .frame(height: 38)
                    .background(V4.accent.opacity(0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle().fill(V4.line.opacity(0.55)).frame(height: 1).padding(.leading, 70)
        }
    }

    private func recentRoomRow(_ room: Room) -> some View {
        Button {
            HapticManager.impact(.light)
            roomToOpen = room
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [V4.accent.opacity(0.35), V4.raised.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "play.rectangle.fill")
                            .foregroundStyle(V4.accent)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(room.name)
                        .font(.system(size: 15, weight: .semibold))
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
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(V4.line.opacity(0.55)).frame(height: 1).padding(.leading, 74)
        }
    }

    private func loadRecentRooms() async {
        recentLoading = true
        defer { recentLoading = false }
        do {
            recentRooms = try await RoomService(api: APIClient.shared).fetchMyRooms()
        } catch {
            // keep previous
        }
    }
}

// MARK: - Friend requests sheet (from header icon)

private struct FriendRequestsSheet: View {
    let theme: V4Theme
    let store: V4FriendsStore
    var onToast: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0x0B1018), Color(hex: 0x0A0D12)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if store.requests.isEmpty && store.outgoing.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "tray")
                                    .font(.system(size: 36))
                                    .foregroundStyle(V4.accent)
                                Text("Нет заявок")
                                    .font(.headline)
                                    .foregroundStyle(V4.ink)
                                Text("Входящие и отправленные запросы появятся здесь")
                                    .font(.subheadline)
                                    .foregroundStyle(V4.muted)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                            .padding(.horizontal, 24)
                        } else {
                            if !store.requests.isEmpty {
                                Text("ВХОДЯЩИЕ")
                                    .font(.system(size: 11, weight: .heavy))
                                    .tracking(0.9)
                                    .foregroundStyle(V4.accent)
                                    .padding(.horizontal, 18)

                                VStack(spacing: 0) {
                                    ForEach(store.requests) { req in
                                        incomingRow(req)
                                    }
                                }
                                .background(V4.surface.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(V4.line))
                                .padding(.horizontal, 16)
                            }

                            if !store.outgoing.isEmpty {
                                Text("ОТПРАВЛЕННЫЕ")
                                    .font(.system(size: 11, weight: .heavy))
                                    .tracking(0.9)
                                    .foregroundStyle(V4.muted)
                                    .padding(.horizontal, 18)
                                    .padding(.top, 8)

                                VStack(spacing: 0) {
                                    ForEach(store.outgoing) { req in
                                        HStack(spacing: 12) {
                                            V4Avatar(letter: String(req.toUser.username.prefix(1)), theme: theme, size: 40)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(req.toUser.username)
                                                    .font(.system(size: 15, weight: .bold))
                                                    .foregroundStyle(V4.ink)
                                                Text("Ожидает ответа")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(V4.muted)
                                            }
                                            Spacer()
                                            Text("⏳")
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .overlay(alignment: .bottom) {
                                            Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 66)
                                        }
                                    }
                                }
                                .background(V4.surface.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(V4.line))
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Заявки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .task { await store.load() }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func incomingRow(_ req: FriendRequest) -> some View {
        HStack(spacing: 12) {
            V4Avatar(letter: String(req.fromUser.username.prefix(1)), theme: theme, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(req.fromUser.username)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(V4.ink)
                Text("хочет добавить вас")
                    .font(.system(size: 12))
                    .foregroundStyle(V4.muted)
            }
            Spacer()
            Button {
                HapticManager.impact(.medium)
                Task {
                    await store.accept(req)
                    onToast("\(req.fromUser.username) в друзьях")
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
                    onToast("Заявка отклонена")
                }
            } label: {
                Text("Нет")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(V4.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(V4.raised.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(V4.line))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 66)
        }
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

                    Text("Друг получит заявку. Открой иконку «Заявки» в шапке, чтобы принять входящие.")
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
                                    Group {
                                        if let url = PlinkAvatarURL.resolve(userId: user.id, stored: user.avatarURL) {
                                            AsyncImage(url: url) { phase in
                                                if let img = phase.image {
                                                    img.resizable().scaledToFill()
                                                } else {
                                                    Circle().fill(V4.accent.opacity(0.25))
                                                        .overlay(
                                                            Text(String(user.username.prefix(1)).uppercased())
                                                                .font(.system(size: 15, weight: .bold))
                                                                .foregroundStyle(.white)
                                                        )
                                                }
                                            }
                                        } else {
                                            Circle().fill(V4.accent.opacity(0.25))
                                                .overlay(
                                                    Text(String(user.username.prefix(1)).uppercased())
                                                        .font(.system(size: 15, weight: .bold))
                                                        .foregroundStyle(.white)
                                                )
                                        }
                                    }
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
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
            // Sheet dismisses so parent top toast is visible
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
            dismiss()
        } else {
            localError = manager.errorMessage ?? "Не удалось отправить"
        }
    }
}
