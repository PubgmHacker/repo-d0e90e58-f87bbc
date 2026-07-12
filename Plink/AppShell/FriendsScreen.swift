// Plink/AppShell/FriendsScreen.swift — GPT-5.6 SOL §8.8
//
// Redesigned Friends screen.
// Title + requests badge; online friends; all friends list; empty state with invite link.

import SwiftUI

struct FriendsScreen: View {
    let dependencies: AppDependencies
    @EnvironmentObject private var friendManager: FriendManager

    var body: some View {
        ZStack {
            Cinema2026.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    // Title
                    HStack {
                        Text("Друзья")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Cinema2026.text)
                        Spacer()
                        if !friendManager.incomingRequests.isEmpty {
                            Text("\(friendManager.incomingRequests.count)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Cinema2026.accent, in: Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Incoming requests
                    if !friendManager.incomingRequests.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Запросы на дружбу")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Cinema2026.text)
                                .padding(.horizontal, 20)

                            ForEach(friendManager.incomingRequests) { request in
                                FriendRequestRow(request: request, friendManager: friendManager)
                                    .padding(.horizontal, 20)
                            }
                        }
                    }

                    // Online friends
                    let onlineFriends = friendManager.friends.filter { $0.isOnline }
                    if !onlineFriends.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("В сети (\(onlineFriends.count))")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Cinema2026.text)
                                .padding(.horizontal, 20)

                            ForEach(onlineFriends) { friend in
                                FriendRow(friend: friend)
                                    .padding(.horizontal, 20)
                            }
                        }
                    }

                    // All friends
                    if !friendManager.friends.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Все друзья (\(friendManager.friends.count))")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Cinema2026.text)
                                .padding(.horizontal, 20)

                            ForEach(friendManager.friends) { friend in
                                FriendRow(friend: friend)
                                    .padding(.horizontal, 20)
                            }
                        }
                    }

                    // Empty state
                    if friendManager.friends.isEmpty && friendManager.incomingRequests.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "person.2")
                                .font(.system(size: 48))
                                .foregroundStyle(Cinema2026.secondary)
                            Text("Друзей пока нет")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Cinema2026.text)
                            Text("Пригласите друзей, чтобы смотреть вместе")
                                .font(.system(size: 14))
                                .foregroundStyle(Cinema2026.secondary)
                                .multilineTextAlignment(.center)
                            Button("Пригласить друга") {
                                // Share sheet
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Cinema2026.accent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 104)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await friendManager.loadAll()
        }
    }
}

// MARK: - Rows

private struct FriendRequestRow: View {
    let request: FriendRequest
    let friendManager: FriendManager

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Cinema2026.surface)
                .frame(width: 44, height: 44)
                .overlay(Text(request.fromUser.username.prefix(1)).font(.system(size: 18, weight: .semibold)).foregroundStyle(Cinema2026.text))

            Text(request.fromUser.username)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Cinema2026.text)

            Spacer()

            Button("✓") {
                Task { await friendManager.acceptRequest(request) }
            }
            .frame(width: 36, height: 36)
            .background(Cinema2026.accent, in: Circle())
            .foregroundStyle(.white)

            Button("✗") {
                Task { await friendManager.declineRequest(request) }
            }
            .frame(width: 36, height: 36)
            .background(Cinema2026.surface, in: Circle())
            .foregroundStyle(Cinema2026.secondary)
        }
        .padding(.vertical, 8)
    }
}

private struct FriendRow: View {
    let friend: Friend

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Cinema2026.surface)
                    .frame(width: 44, height: 44)
                    .overlay(Text(friend.username.prefix(1)).font(.system(size: 18, weight: .semibold)).foregroundStyle(Cinema2026.text))

                if friend.isOnline {
                    Circle()
                        .fill(Cinema2026.accent)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Cinema2026.background, lineWidth: 2))
                }
            }

            Text(friend.username)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Cinema2026.text)

            Spacer()

            if friend.isOnline {
                Text("В сети")
                    .font(.system(size: 12))
                    .foregroundStyle(Cinema2026.accent)
            }
        }
        .padding(.vertical, 8)
    }
}
