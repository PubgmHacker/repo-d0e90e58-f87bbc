// Plink/Views/Friends/FriendProfileView.swift — simplified, no V4 deps
import SwiftUI

struct FriendProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let friend: Friend
    var onInvite: (() -> Void)?
    var onMessage: (() -> Void)?
    var onBlock: (() -> Void)?
    var onReport: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Circle().fill(Cinema2026.surface).frame(width: 90, height: 90)
                            .overlay(Text(friend.username.prefix(1)).font(.system(size: 36, weight: .semibold)).foregroundStyle(Cinema2026.text))
                        Text(friend.username).font(.system(size: 22, weight: .bold)).foregroundStyle(Cinema2026.text)
                        if friend.isOnline { Text("В сети").font(.system(size: 13)).foregroundStyle(Cinema2026.accent) }
                    }
                    .padding(.top, 20)

                    HStack(spacing: 12) {
                        Button("Позвать смотреть") { onInvite?() }
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(Cinema2026.background)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Cinema2026.accent, in: RoundedRectangle(cornerRadius: 16))
                        Button("Сообщение") { onMessage?() }
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(Cinema2026.text)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Cinema2026.divider, lineWidth: 0.5))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Безопасность").font(.system(size: 14, weight: .semibold)).foregroundStyle(Cinema2026.secondary)
                        Button(role: .destructive) { onBlock?() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "hand.raised").font(.system(size: 16)).foregroundStyle(Cinema2026.danger).frame(width: 28)
                                Text("Заблокировать").font(.system(size: 16)).foregroundStyle(Cinema2026.danger)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Cinema2026.secondary)
                            }.padding(.horizontal, 16).frame(height: 50)
                        }
                        .buttonStyle(.plain)
                        .background(Cinema2026.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 32)
            }
            .navigationTitle(friend.username)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }
}
