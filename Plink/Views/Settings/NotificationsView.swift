import SwiftUI

// MARK: - Notifications Settings View
/// Экран настроек уведомлений.
struct NotificationsView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var pushNotifications = true
    @State private var notificationSounds = true
    @State private var friendsOnline = false
    @State private var newRooms = true

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        // Уведомления
                        settingsCard {
                            ToggleRow(
                                icon: "bell.badge.fill",
                                title: loc.string(.notifPush),
                                subtitle: loc.string(.notifPushSubtitle),
                                isOn: $pushNotifications
                            )
                            Divider().padding(.leading, 52)
                            ToggleRow(
                                icon: "speaker.wave.2.fill",
                                title: loc.string(.notifSounds),
                                subtitle: loc.string(.notifSoundsSubtitle),
                                isOn: $notificationSounds
                            )
                            Divider().padding(.leading, 52)
                            ToggleRow(
                                icon: "person.wave.2",
                                title: loc.string(.notifFriendsOnline),
                                subtitle: loc.string(.notifFriendsOnlineSubtitle),
                                isOn: $friendsOnline
                            )
                            Divider().padding(.leading, 52)
                            ToggleRow(
                                icon: "plus.circle.fill",
                                title: loc.string(.notifNewRooms),
                                subtitle: loc.string(.notifNewRoomsSubtitle),
                                isOn: $newRooms
                            )
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle(loc.string(.notifTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.ravePrimary)
                    }
                }
            }
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(Color.raveCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.raveSurface, lineWidth: 1)
            )
    }
}

// MARK: - Toggle Row
private struct ToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(.ravePrimary)
                    .frame(width: 30, height: 30)
                    .background(Color.ravePrimary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.raveTextPrimary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.raveTextSecondary)
                }
            }
        }
        .tint(.raveWarning)
        .padding(.vertical, 4)
    }
}
