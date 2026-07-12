// Plink/Views/Friends/FriendProfileView.swift — GPT-5.6 V4 §8

import SwiftUI

struct FriendProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlinkThemeStore.self) private var themeStore
    let friend: Friend
    var onInvite: (() -> Void)?
    var onMessage: (() -> Void)?
    var onBlock: (() -> Void)?
    var onReport: (() -> Void)?

    var body: some View {
        V4SecondaryScreen(surface: .friends, title: friend.username, dismiss: dismiss.callAsFunction) {
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Hero
                    VStack(spacing: 12) {
                        Circle()
                            .fill(Cinema2026.surface)
                            .frame(width: 90, height: 90)
                            .overlay(Text(friend.username.prefix(1)).font(.system(size: 36, weight: .semibold)).foregroundStyle(Cinema2026.text))
                        Text(friend.username)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Cinema2026.text)
                        if friend.isOnline {
                            Text("В сети")
                                .font(.system(size: 13))
                                .foregroundStyle(Cinema2026.accent)
                        }
                    }
                    .padding(.top, 20)

                    // Actions
                    HStack(spacing: 12) {
                        Button("Позвать смотреть", action: { onInvite?() })
                            .buttonStyle(V4PrimaryButtonStyle())
                        Button("Сообщение", action: { onMessage?() })
                            .buttonStyle(V4SecondaryButtonStyle())
                    }

                    // Safety
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Безопасность").font(.system(size: 14, weight: .semibold)).foregroundStyle(Cinema2026.secondary)
                        VStack(spacing: 0) {
                            SettingsRow(icon: "hand.raised", title: "Заблокировать", role: .destructive) { onBlock?() }
                        }
                        .background(Cinema2026.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 32)
            }
        }
    }
}
