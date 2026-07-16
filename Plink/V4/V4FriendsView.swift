// Plink/V4/V4FriendsView.swift — friends list + server-backed add/accept flow

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
                VStack(spacing:0) {
                    friend("А","Алина","смотрит Afterglow","Войти")
                    friend("М","Миша","готов смотреть","Позвать")
                }.padding(.horizontal,19)
            }.padding(.bottom,92)
        }.foregroundStyle(V4.ink)
    }
    private func friend(_ letter:String,_ name:String,_ status:String,_ action:String)->some View {
        HStack(spacing:11) {
            V4Avatar(letter:letter,theme:theme,size:39)
            VStack(alignment:.leading,spacing:2) { Text(name).font(.system(size:13.6,weight:.bold)); Text(status).font(.system(size:11.52)).foregroundStyle(V4.muted) }
            Spacer()
            Button(action){}.font(.system(size:11.52)).foregroundStyle(V4.ink).padding(.horizontal,10).frame(height:35)
                .background(V4.surface).clipShape(RoundedRectangle(cornerRadius:11)).overlay(RoundedRectangle(cornerRadius:11).stroke(V4.line))
        }.frame(minHeight:61).overlay(alignment:.bottom){ Rectangle().fill(V4.line).frame(height:1) }
    }
}

// MARK: - Live friends (server-synced)

struct V4FriendsViewLive: View {
    let theme: V4Theme
    var store: V4FriendsStore?
    @State private var dmFriend: Friend?
    @State private var profileFriend: Friend?
    @State private var showCreateRoom = false
    @State private var watchWithFriend: Friend?
    @State private var showAddFriend = false
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators:false) {
                VStack(spacing:0) {
                    HStack(alignment:.top) {
                        V4Heading(eyebrow:"МЕССЕНДЖЕР",title:"Друзья и чаты")
                        Spacer()
                        Button {
                            HapticManager.impact(.light)
                            showAddFriend = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(V4.accent)
                                .frame(width: 40, height: 40)
                                .background(V4.surface.opacity(0.85))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(V4.line))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Добавить друга")
                    }
                    .padding(.horizontal,18).padding(.top,10).padding(.bottom,8)

                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.plus")
                            .foregroundStyle(V4.accent)
                        Text("«+» — найти по @username и отправить заявку. Входящие заявки — принять или отклонить.")
                            .font(.system(size: 12))
                            .foregroundStyle(V4.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(V4.surface.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(V4.line))
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)

                    // ── Incoming friend requests ──
                    if let s = store, !s.requests.isEmpty {
                        sectionTitle("Входящие заявки", badge: s.requests.count)
                        VStack(spacing: 0) {
                            ForEach(s.requests) { req in
                                incomingRow(req, store: s)
                            }
                        }
                        .padding(.horizontal, 19)
                        .padding(.bottom, 16)
                    }

                    // ── Outgoing (pending) ──
                    if let s = store, !s.outgoing.isEmpty {
                        sectionTitle("Отправленные", badge: nil)
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
                                    Text("⏳")
                                        .font(.system(size: 14))
                                }
                                .frame(minHeight: 56)
                                .overlay(alignment: .bottom) { Rectangle().fill(V4.line).frame(height: 1) }
                            }
                        }
                        .padding(.horizontal, 19)
                        .padding(.bottom, 16)
                    }

                    // ── Friends list ──
                    if let s = store {
                        switch s.state {
                        case .loading:
                            ProgressView().tint(V4.accent).padding(.top, 40)
                        case .loaded, .empty:
                            if s.friends.isEmpty && s.requests.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "person.2")
                                        .font(.largeTitle)
                                        .foregroundStyle(V4.accent)
                                    Text("Друзей пока нет")
                                        .font(.headline)
                                    Text("Нажми «+» и найди друга по @username")
                                        .font(.subheadline)
                                        .foregroundStyle(V4.muted)
                                        .multilineTextAlignment(.center)
                                    Button {
                                        showAddFriend = true
                                    } label: {
                                        Text("Добавить друга")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(V4.accentInk)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 12)
                                            .background(V4.accent, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 4)
                                }
                                .padding(.top, 40)
                                .padding(.horizontal, 24)
                            } else if !s.friends.isEmpty {
                                sectionTitle("Друзья", badge: s.friends.count)
                                VStack(spacing: 0) {
                                    ForEach(s.friends) { friend in
                                        friendRow(friend)
                                    }
                                }
                                .padding(.horizontal, 19)
                            }
                        case .failed(let error):
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(V4.muted)
                                .padding(.top, 40)
                        case .idle:
                            Color.clear.frame(height: 40)
                        }
                    } else {
                        ProgressView().tint(V4.accent).padding(.top, 40)
                    }

                    Color.clear.frame(height: 92)
                }
            }
            .foregroundStyle(V4.ink)
            .background(Color.clear)
            .scrollContentBackground(.hidden)
            .refreshable {
                await store?.load()
            }
            .navigationDestination(item: $dmFriend) { friend in
                DMChatView(friend: friend)
                    .environmentObject(DMChatService(api: APIClient.shared))
            }
            .navigationDestination(item: $profileFriend) { friend in
                FriendProfileView(userId: friend.id, usernameHint: friend.username) {
                    watchWithFriend = friend
                    showCreateRoom = true
                }
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
                    }
                } else {
                    Text("Загрузка…").padding()
                }
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
            .toolbarBackground(.hidden, for: .navigationBar)
            .task {
                await store?.load()
            }
        }
        .background(Color.clear)
        .background(V4TransparentNavBackground())
    }

    // MARK: - Rows

    private func sectionTitle(_ title: String, badge: Int?) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .bold))
            if let badge, badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(V4.accentInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(V4.accent, in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 19)
        .padding(.bottom, 8)
        .padding(.top, 4)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Заявка от \(req.fromUser.username)")
    }

    private func friendRow(_ friend: Friend) -> some View {
        HStack(spacing: 11) {
            Button { profileFriend = friend } label: {
                V4Avatar(letter: String(friend.username.prefix(1)), theme: theme, size: 39)
            }
            .buttonStyle(.plain)

            Button { dmFriend = friend } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.username).font(.system(size: 13.6, weight: .bold)).foregroundStyle(V4.ink)
                    Text(friend.isOnline ? "В сети · открыть чат" : "Не в сети · открыть чат")
                        .font(.system(size: 11.52)).foregroundStyle(V4.muted)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button { dmFriend = friend } label: {
                Image(systemName: "message.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(V4.ink)
                    .frame(width: 35, height: 35)
                    .background(V4.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(V4.line))
            }
            .buttonStyle(.plain)

            Button {
                HapticManager.impact(.light)
                watchWithFriend = friend
                showCreateRoom = true
            } label: {
                Text("Смотреть")
                    .font(.system(size: 11.52))
                    .foregroundStyle(V4.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 35)
            }
            .buttonStyle(.plain)
            .background(V4.surface)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(V4.line))
        }
        .frame(minHeight: 61)
        .overlay(alignment: .bottom) { Rectangle().fill(V4.line).frame(height: 1) }
    }
}

// MARK: - Add Friend Sheet (search + send request via API)

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
                // Direct @username send
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
                                ProgressView().tint(V4.accentInk)
                                    .frame(width: 48, height: 48)
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
                        .accessibilityLabel("Отправить заявку")
                    }

                    Text("Друг получит заявку и сможет принять или отклонить.")
                        .font(.system(size: 12))
                        .foregroundStyle(V4.muted)
                }
                .padding(18)

                Divider().overlay(V4.line)

                // Search
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
                                        Text("Друг")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(V4.muted)
                                    } else if manager.hasOutgoingRequest(to: user.id) {
                                        Text("Отправлено")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(V4.amber)
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
            .onAppear {
                manager.errorMessage = nil
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
            let msg = manager.lastSuccessMessage ?? "Заявка отправлена"
            onDone(msg)
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
            let msg = manager.lastSuccessMessage ?? "Заявка отправлена"
            onDone(msg)
            // keep sheet open so user can add more; refresh search state
            await manager.searchUsers(query: query)
        } else {
            localError = manager.errorMessage ?? "Не удалось отправить"
        }
    }
}

/// Clears UIKit NavigationStack chrome so Plink living / live themes stay visible.
private struct V4TransparentNavBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            var parent = view.superview
            for _ in 0..<8 {
                guard let p = parent else { break }
                p.backgroundColor = .clear
                if let nav = p as? UINavigationController {
                    nav.view.backgroundColor = .clear
                    nav.navigationBar.isTranslucent = true
                }
                if String(describing: type(of: p)).contains("Navigation") {
                    p.backgroundColor = .clear
                }
                parent = p.superview
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
