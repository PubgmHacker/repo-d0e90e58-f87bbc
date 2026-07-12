// Plink/Views/Home/RoomCreationView.swift — GPT-5.6 V4 §2
// V4 redesign. Preserves existing state machine + provider callbacks.

import SwiftUI

struct RoomCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var apiClient: APIClient
    var friendManager: FriendManager? = nil
    var intent: CreateRoomIntent? = nil
    var onRoomCreated: (Room) -> Void

    @State private var currentStep: CreationStep = .service
    @State private var selectedService: VideoService = .youtube
    @State private var mediaURL = ""
    @State private var mediaTitle = ""
    @State private var resolvedMediaItem: MediaItem?
    @State private var roomName = ""
    @State private var maxParticipants = 4
    @State private var privacy: RoomPrivacy = .publicRoom
    @State private var selectedFriendIds: Set<String> = []
    @State private var isCreating = false
    @State private var roomSetupConfig: RoomSetupConfig?
    @State private var nameError: String?
    @State private var urlError: String?
    @State private var selectedThemeID: String = PlinkThemeCatalog.defaultID

    enum CreationStep: String, CaseIterable {
        case service, details, invite
        var next: CreationStep? {
            switch self { case .service: .details; case .details: .invite; case .invite: nil }
        }
        var previous: CreationStep? {
            switch self { case .service: nil; case .details: .service; case .invite: .details }
        }
    }

    struct RoomSetupConfig: Identifiable {
        let id = UUID()
        let service: VideoService
        let contentURL: String
        let contentTitle: String
        let thumbnailURL: String?
    }

    private var isPremium: Bool { PremiumStatusManager.shared.isPremium }

    var body: some View {
        V4Surface(theme: PlinkThemeCatalog.resolve(nil), surface: .rooms) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Cinema2026.text).frame(width: 44, height: 44)
                    }
                    Spacer()
                    Text("Новая комната").font(.system(size: 17, weight: .semibold)).foregroundStyle(Cinema2026.text)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)

                switch currentStep {
                case .service:
                    serviceStep
                case .details:
                    detailsStep
                case .invite:
                    inviteStep
                }
            }
        }
        .onAppear {
            if roomSetupConfig == nil, case .selectedContent(let draft) = intent {
                roomSetupConfig = RoomSetupConfig(service: draft.service, contentURL: draft.contentURL, contentTitle: draft.title, thumbnailURL: draft.thumbnailURL)
                currentStep = .details
            }
        }
        .fullScreenCover(item: $roomSetupConfig) { config in
            roomSetupView(config)
        }
    }

    // MARK: - Service step
    private var serviceStep: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                V4ScreenHeader(eyebrow: "НОВАЯ КОМНАТА", title: "Выберите сервис")

                // YouTube (available)
                serviceRow(icon: "play.rectangle.fill", title: "YouTube", subtitle: "Поиск и выбор видео", available: true) {
                    selectedService = .youtube
                    showYouTubeSearch()
                }

                // Rutube (available)
                serviceRow(icon: "play.tv.fill", title: "Rutube", subtitle: "Поиск видео", available: true) {
                    selectedService = .rutube
                    currentStep = .details
                }

                // Browser (future)
                serviceRow(icon: "safari.fill", title: "Браузер", subtitle: "Скоро", available: false) { }

                // URL paste
                serviceRow(icon: "link", title: "Вставить ссылку", subtitle: "YouTube / Rutube URL", available: true) {
                    selectedService = .youtube
                    currentStep = .details
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 32)
        }
    }

    private func serviceRow(icon: String, title: String, subtitle: String, available: Bool, action: @escaping () -> Void) -> some View {
        Button(action: available ? action : {}) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(available ? Cinema2026.accent : Cinema2026.secondary)
                    .frame(width: 44, height: 44)
                    .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(available ? Cinema2026.text : Cinema2026.secondary)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Cinema2026.secondary)
                }
                Spacer()
                if available { Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Cinema2026.secondary) }
            }
            .padding(14)
            .background(Cinema2026.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(!available)
    }

    // MARK: - Details step
    private var detailsStep: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                V4ScreenHeader(eyebrow: "НАСТРОЙКА", title: "Оформите комнату")

                if let config = roomSetupConfig {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Выбранное видео").font(.system(size: 14, weight: .semibold)).foregroundStyle(Cinema2026.secondary)
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: config.thumbnailURL ?? "")) { img in img.resizable().aspectRatio(contentMode: .fill) } placeholder: { Rectangle().fill(Cinema2026.surface) }
                                .frame(width: 80, height: 45).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(config.contentTitle).font(.system(size: 14, weight: .medium)).foregroundStyle(Cinema2026.text).lineLimit(2)
                                Text(config.service.rawValue).font(.system(size: 12)).foregroundStyle(Cinema2026.secondary)
                            }
                            Spacer()
                        }
                        .padding(12).background(Cinema2026.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                // Room name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Название комнаты").font(.system(size: 14, weight: .semibold)).foregroundStyle(Cinema2026.secondary)
                    TextField("Комната друзей", text: $roomName).v4InputStyle()
                }

                // Privacy
                VStack(alignment: .leading, spacing: 8) {
                    Text("Приватность").font(.system(size: 14, weight: .semibold)).foregroundStyle(Cinema2026.secondary)
                    HStack(spacing: 10) {
                        privacyChip("Публичная", isSelected: privacy == .publicRoom) { privacy = .publicRoom }
                        privacyChip("Приватная", isSelected: privacy == .privateRoom) { privacy = .privateRoom }
                    }
                }

                // Theme picker
                RoomThemePicker(hasPremium: isPremium, selectedID: $selectedThemeID, openPaywall: { })

                // Create button
                Button {
                    Task { await createRoom() }
                } label: {
                    HStack {
                        if isCreating { ProgressView().tint(Cinema2026.background) }
                        Text("Создать комнату")
                    }
                }
                .buttonStyle(V4PrimaryButtonStyle())
                .disabled(roomName.isEmpty || isCreating)
            }
            .padding(.horizontal, 20).padding(.bottom, 32)
        }
    }

    private func privacyChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? Cinema2026.background : Cinema2026.text)
                .padding(.horizontal, 16).frame(height: 40)
                .background(isSelected ? Cinema2026.accent : Cinema2026.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Invite step
    private var inviteStep: some View {
        VStack(spacing: 20) {
            V4ScreenHeader(eyebrow: "ПОЧТИ ГОТОВО", title: "Пригласите друзей")
            Spacer()
            Text("Комната создана! Поделитесь кодом с друзьями.")
                .font(.system(size: 16)).foregroundStyle(Cinema2026.secondary).multilineTextAlignment(.center)
            Spacer()
            Button("Готово") { dismiss() }.buttonStyle(V4PrimaryButtonStyle())
        }
        .padding(.horizontal, 20).padding(.bottom, 32)
    }

    // MARK: - Actions
    private func showYouTubeSearch() {
        selectedService = .youtube
        currentStep = .details
    }

    private func roomSetupView(_ config: RoomSetupConfig) -> some View {
        VStack { Text("Setup: \(config.contentTitle)") }
    }

    private func createRoom() async {
        isCreating = true
        defer { isCreating = false }
        let contentURL = roomSetupConfig?.contentURL ?? mediaURL
        let title = roomSetupConfig?.contentTitle ?? mediaTitle
        let thumb = roomSetupConfig?.thumbnailURL ?? "https://img.youtube.com/vi/\(contentURL)/mqdefault.jpg"

        let mediaItem = MediaItem(
            id: contentURL,
            title: title,
            artist: nil,
            thumbnailURL: thumb,
            streamURL: contentURL,
            duration: nil,
            mediaType: .video,
            source: .youtube
        )

        let request = CreateRoomRequest(
            name: roomName.isEmpty ? "Комната" : roomName,
            maxParticipants: maxParticipants,
            mediaItem: mediaItem,
            privacy: privacy,
            password: nil,
            hostName: nil
        )

        do {
            let room = try await dependencies_roomService().createRoom(request)
            onRoomCreated(room)
            dismiss()
        } catch {
            nameError = "Ошибка: \(error.localizedDescription)"
        }
    }

    private func dependencies_roomService() -> RoomService {
        // Use the API client to create a room service
        return RoomService(api: apiClient)
    }
}
