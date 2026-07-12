import SwiftUI

// ═══════════════════════════════════════════════════════════════════════
// MARK: - Chat Appearance Sheet (v11 — July 2026)
// ═══════════════════════════════════════════════════════════════════════
//
// Top-level sheet for "Оформление чата" settings section. Contains two
// subsections, each opens its own BubbleStylePickerSheet:
//   1. "В чате с друзьями" — DM (Direct Messages) bubble style
//   2. "В комнате для просмотра" — Room (movie room) bubble style
//
// Currently both subsections share the SAME BubbleStylePreference
// (single user-selected style). Future enhancement: separate preferences
// for DM vs Room. The backend already supports per-message bubbleStyle
// in the WS payload, so client-side split is just a matter of two
// UserDefaults keys + two pickers.
//
// Permission model mirrors BubbleStylePermissions:
//   - Non-premium users see only "default" style in picker, locked styles
//     open paywall.
//   - Premium users see default + cute_duck + neon_cyber.
//   - Admins see picker too but their messages auto-use admin_bubble.

struct ChatAppearanceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let isPremium: Bool
    let isAdmin: Bool
    var onPick: (BubbleStyle) -> Void
    var onLockedTap: () -> Void

    @State private var showDMPicker = false
    @State private var showRoomPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                Cinema2026.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Header banner
                        chatAppearanceHeader

                        // ── Subsection 1: DM (friends) ──
                        subsectionCard(
                            icon: "person.2.fill",
                            title: "В чате с друзьями",
                            subtitle: "Личные сообщения и групповые чаты с друзьями",
                            currentStyle: BubbleStylePreference.get().displayName
                        ) {
                            showDMPicker = true
                        }

                        // ── Subsection 2: Room (movie rooms) ──
                        subsectionCard(
                            icon: "play.rectangle.on.rectangle.fill",
                            title: "В комнате для просмотра",
                            subtitle: "Сообщения в комнатах совместного просмотра фильмов",
                            currentStyle: BubbleStylePreference.get().displayName
                        ) {
                            showRoomPicker = true
                        }

                        // Premium upsell banner (for non-premium users)
                        if !isPremium && !isAdmin {
                            premiumUpsellBanner
                        }

                        // Admin banner
                        if isAdmin {
                            adminInfoBanner
                        }

                        // Footer
                        Text("Выбранный стиль применяется ко всем вашим сообщениям. Сервер проверяет права — стили, недоступные вашей подписке, будут сброшены к «Стандартный».")
                            .font(.system(size: 11))
                            .foregroundColor(.raveTextTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Оформление чата")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundColor(.bioAmber)
                }
            }
            .toolbarBackground(Color.clear, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showDMPicker) {
            BubbleStylePickerSheet(
                isPremium: isPremium,
                isAdmin: isAdmin,
                onPick: onPick,
                onLockedTap: onLockedTap
            )
        }
        .sheet(isPresented: $showRoomPicker) {
            BubbleStylePickerSheet(
                isPremium: isPremium,
                isAdmin: isAdmin,
                onPick: onPick,
                onLockedTap: onLockedTap
            )
        }
    }

    // MARK: - Header

    private var chatAppearanceHeader: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.bioAmber.opacity(0.2))
                    .frame(width: 56, height: 56)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.bioAmber)
            }
            Text("Кастомные стили сообщений")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text("Выберите уникальное оформление для своих сообщений в разных чатах")
                .font(.system(size: 12))
                .foregroundColor(.raveTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 12)
    }

    // MARK: - Subsection Card

    @ViewBuilder
    private func subsectionCard(
        icon: String,
        title: String,
        subtitle: String,
        currentStyle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.bioAmber.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(.bioAmber)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.raveTextPrimary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.raveTextSecondary)
                        .lineLimit(2)
                    Text("Текущий: \(currentStyle)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.bioAmber)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.raveTextTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.bioAmber.opacity(0.15), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Premium Upsell

    private var premiumUpsellBanner: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundColor(.bioAmber)
                Text("Плинк+")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.bioAmber)
                Spacer()
            }
            Text("Подпишитесь на Плинк+, чтобы получить доступ к уникальным стилям пузырей: милой уточке, неоновому киберпанку и другим.")
                .font(.system(size: 11))
                .foregroundColor(.raveTextSecondary)
                .multilineTextAlignment(.leading)
            Button {
                onLockedTap()
            } label: {
                Text("Оформить подписку")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.bioAmber)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.bioAmber.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Admin Info

    private var adminInfoBanner: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.yellow)
                Text("Режим администратора")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.yellow)
                Spacer()
            }
            Text("Ваши сообщения автоматически используют VIP-стиль (чёрный матовый + золотая неоновая рамка). Выбор выше — только для предпросмотра стилей доступных обычным пользователям.")
                .font(.system(size: 11))
                .foregroundColor(.raveTextSecondary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

#Preview {
    ChatAppearanceSheet(
        isPremium: false,
        isAdmin: false,
        onPick: { _ in },
        onLockedTap: {}
    )
}

#Preview("Premium") {
    ChatAppearanceSheet(
        isPremium: true,
        isAdmin: false,
        onPick: { _ in },
        onLockedTap: {}
    )
}

#Preview("Admin") {
    ChatAppearanceSheet(
        isPremium: true,
        isAdmin: true,
        onPick: { _ in },
        onLockedTap: {}
    )
}
