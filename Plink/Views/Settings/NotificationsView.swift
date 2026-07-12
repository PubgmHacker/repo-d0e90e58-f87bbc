import SwiftUI

// MARK: - Notifications Settings View (Premium)
/// 🔧 Pack v3: Убран NavigationStack (используется родительский из SettingsView).
struct NotificationsView: View {
    @ObservedObject private var loc = LocalizationManager.shared

    // Persisted state (UserDefaults-backed)
    @AppStorage("notif_push_enabled") private var pushNotifications = true
    @AppStorage("notif_sounds_enabled") private var notificationSounds = true
    @AppStorage("notif_friends_online") private var friendsOnline = false
    @AppStorage("notif_new_rooms") private var newRooms = true
    @AppStorage("notif_friend_requests") private var friendRequests = true
    @AppStorage("notif_room_invites") private var roomInvites = true
    @AppStorage("notif_mentions") private var mentions = true
    @AppStorage("notif_do_not_disturb") private var doNotDisturb = false

    var body: some View {
        ZStack {
            Cinema2026.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // ── DND banner ──
                    if doNotDisturb {
                        HStack(spacing: 10) {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.raveWarning)
                            Text("Режим «Не беспокоить» включён — вы не получите никаких уведомлений.")
                                .font(.system(size: 12))
                                .foregroundColor(.raveTextSecondary)
                        }
                        .padding(12)
                        .background(Color.raveWarning.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.raveWarning.opacity(0.2), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 16)
                    }

                    // ── General Section ──
                    VStack(alignment: .leading, spacing: 6) {
                        PlinkSectionHeader(text: "Общие")
                        PlinkSettingsCard {
                            PlinkToggleRow(
                                icon: "moon.fill",
                                title: "Не беспокоить",
                                subtitle: "Отключить все уведомления",
                                iconColor: .raveWarning,
                                isOn: $doNotDisturb
                            )
                            PlinkToggleRow(
                                icon: "bell.badge.fill",
                                title: loc.string(.notifPush),
                                subtitle: loc.string(.notifPushSubtitle),
                                iconColor: .bioCyan,
                                isOn: $pushNotifications,
                                enabled: !doNotDisturb
                            )
                            PlinkToggleRow(
                                icon: "speaker.wave.2.fill",
                                title: loc.string(.notifSounds),
                                subtitle: loc.string(.notifSoundsSubtitle),
                                iconColor: .bioEmerald,
                                isOn: $notificationSounds,
                                enabled: !doNotDisturb
                            )
                        }
                    }

                    // ── Friends & Social Section ──
                    VStack(alignment: .leading, spacing: 6) {
                        PlinkSectionHeader(text: "Друзья и соцсети")
                        PlinkSettingsCard {
                            PlinkToggleRow(
                                icon: "person.wave.2",
                                title: loc.string(.notifFriendsOnline),
                                subtitle: loc.string(.notifFriendsOnlineSubtitle),
                                iconColor: .bioTeal,
                                isOn: $friendsOnline,
                                enabled: !doNotDisturb
                            )
                            PlinkToggleRow(
                                icon: "person.badge.plus",
                                title: "Запросы в друзья",
                                subtitle: "Когда кто-то хочет добавить вас",
                                iconColor: .bioCyan,
                                isOn: $friendRequests,
                                enabled: !doNotDisturb
                            )
                            PlinkToggleRow(
                                icon: "envelope.fill",
                                title: "Приглашения в комнаты",
                                subtitle: "Когда друзья зовут вас смотреть вместе",
                                iconColor: .bioEmerald,
                                isOn: $roomInvites,
                                enabled: !doNotDisturb
                            )
                        }
                    }

                    // ── Rooms & Content Section ──
                    VStack(alignment: .leading, spacing: 6) {
                        PlinkSectionHeader(text: "Комнаты и контент")
                        PlinkSettingsCard {
                            PlinkToggleRow(
                                icon: "plus.circle.fill",
                                title: loc.string(.notifNewRooms),
                                subtitle: loc.string(.notifNewRoomsSubtitle),
                                iconColor: .bioTeal,
                                isOn: $newRooms,
                                enabled: !doNotDisturb
                            )
                            PlinkToggleRow(
                                icon: "at",
                                title: "Упоминания в чате",
                                subtitle: "Когда кто-то упоминает вас в чате комнаты",
                                iconColor: .bioCyan,
                                isOn: $mentions,
                                enabled: !doNotDisturb
                            )
                        }
                    }

                    // ── Footer Info ──
                    Text("Настройки уведомлений сохраняются на этом устройстве. Push-уведомления доставляются через Apple Push Notification Service.")
                        .font(.system(size: 11))
                        .foregroundColor(.raveTextTertiary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Уведомления")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
    }
}
