// Plink/Views/Home/RoomCreationView.swift — V5 state machine
// Implements GPT-5.6 P0.2: 4-step flow (service → content → settings → create)
// All paths funnel through RoomPresentationCoordinator.

import SwiftUI

struct RoomCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var apiClient: APIClient
    var onRoomCreated: (Room) -> Void
    /// When set (Friends → «Смотреть»), prefill name and show invite hint.
    var inviteFriend: Friend? = nil

    @State private var step: Step = .service
    @State private var selectedService: VideoService = .youtube
    @State private var mediaURL: String = ""
    @State private var mediaTitle: String = ""
    @State private var mediaThumbnail: String?
    @State private var mediaVideoId: String?  // for YouTube
    @State private var roomName: String = ""
    @State private var maxParticipants: Int = 4
    @State private var privacy: RoomPrivacy = .publicRoom
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showYouTubeSearch = false
    @State private var authWallService: VideoService?
    @State private var pendingAuthAction: PendingAuthAction?

    enum Step: String, CaseIterable {
        case service, content, settings, creating
    }

    private enum PendingAuthAction {
        case continueToSettings
        case fastYouTube(videoId: String, title: String, thumbnail: String?)
        case createRoom
    }

    private var isPremium: Bool { PremiumStatusManager.shared.isPremium }

    var body: some View {
        NavigationStack {
            Cinema2026.background.ignoresSafeArea().overlay {
                VStack(spacing: 0) {
                    progressBar
                    ScrollView {
                        switch step {
                        case .service: serviceStep
                        case .content: contentStep
                        case .settings: settingsStep
                        case .creating: creatingStep
                        }
                    }
                }
            }
            .navigationTitle("Новая комната")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                if step != .service && step != .creating {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Назад") { goBack() }
                    }
                }
            }
            .sheet(isPresented: $showYouTubeSearch) {
                YouTubeSearchView { videoId, title, thumb in
                    beginFastYouTubeCreate(videoId: videoId, title: title, thumbnail: thumb)
                }
            }
            .overlay {
                if let service = authWallService {
                    ServiceAuthView(
                        service: service,
                        onAuthorized: {
                            ServiceAuthStore.markAuthorized(service.serviceType)
                            authWallService = nil
                            resumePendingAuthAction()
                        },
                        onCancel: {
                            pendingAuthAction = nil
                            authWallService = nil
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(20)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.88), value: authWallService?.id)
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(Step.allCases.filter { $0 != .creating }, id: \.self) { s in
                Capsule()
                    .fill(stepIndex(s) <= stepIndex(step) ? Cinema2026.accent : Cinema2026.surface)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func stepIndex(_ s: Step) -> Int {
        switch s {
        case .service: return 0
        case .content: return 1
        case .settings: return 2
        case .creating: return 3
        }
    }

    private func goBack() {
        switch step {
        case .content: step = .service
        case .settings: step = .content
        default: break
        }
    }

    // MARK: - Step 1: Service

    private var serviceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ВЫБОР СЕРВИСА")
                .font(.caption2.bold())
                .tracking(1.1)
                .foregroundStyle(Cinema2026.accent)
            Text("Что смотрим?")
                .font(.largeTitle.bold())
                .foregroundStyle(Cinema2026.text)

            Text("ПРЯМОЙ SYNC")
                .font(.caption2.bold())
                .tracking(1.1)
                .foregroundStyle(Cinema2026.secondary)

            ForEach(syncableServices, id: \.self) { svc in
                serviceCard(svc, kind: .direct)
            }

            // OTT / cinemas: host subscription — guests still sync via Plink (product strategy)
            Text("КИНОТЕАТРЫ · ПОДПИСКА HOST")
                .font(.caption2.bold())
                .tracking(1.1)
                .foregroundStyle(Cinema2026.secondary)
                .padding(.top, 8)

            Text("Host входит в свой аккаунт. Гости смотрят синхронно в Plink.")
                .font(.system(size: 12))
                .foregroundStyle(Cinema2026.secondary.opacity(0.9))

            ForEach(cinemaServices, id: \.self) { svc in
                serviceCard(svc, kind: .subscription)
            }

            Text("ДРУГОЕ")
                .font(.caption2.bold())
                .tracking(1.1)
                .foregroundStyle(Cinema2026.secondary)
                .padding(.top, 8)

            ForEach(otherServices, id: \.self) { svc in
                serviceCard(svc, kind: .other)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 32)
    }

    private var syncableServices: [VideoService] {
        [.youtube, .vk, .rutube]
    }

    private var cinemaServices: [VideoService] {
        [.netflix, .disney, .kinopoisk, .ivi, .okko, .wink, .start, .premier, .smotrim, .kion]
    }

    private var otherServices: [VideoService] {
        [.customURL, .browser]
    }

    private enum ServiceCardKind {
        case direct        // YouTube / VK / Rutube
        case subscription  // Netflix / RU cinemas — host sub, guests sync
        case other
    }

    private func serviceCard(_ svc: VideoService, kind: ServiceCardKind) -> some View {
        Button {
            selectedService = svc
            step = .content
        } label: {
            HStack(spacing: 14) {
                Image(systemName: svc.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(svc.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(svc.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Cinema2026.text)
                        if kind == .subscription {
                            Text("подписка host")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Cinema2026.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Cinema2026.accent.opacity(0.15), in: Capsule())
                        } else if kind == .direct {
                            Text("sync")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(hex: 0x26D9A4))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: 0x26D9A4).opacity(0.15), in: Capsule())
                        }
                    }
                    Text(svc.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Cinema2026.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Cinema2026.secondary)
            }
            .padding(14)
            .background(Cinema2026.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: Content

    private var contentStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ВЫБОР КОНТЕНТА")
                .font(.caption2.bold())
                .tracking(1.1)
                .foregroundStyle(Cinema2026.accent)
            Text("Что именно смотрим?")
                .font(.largeTitle.bold())
                .foregroundStyle(Cinema2026.text)
            Text(selectedService.title)
                .font(.subheadline)
                .foregroundStyle(Cinema2026.secondary)

            // YouTube / VK / Rutube: search button + paste URL section
            if selectedService == .youtube || selectedService == .vk || selectedService == .rutube {
                if selectedService == .youtube {
                    Button {
                        showYouTubeSearch = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 20))
                            Text("Найти на \(selectedService.title)")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(Cinema2026.text)
                        .padding(16)
                        .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    serviceBrandCarousel
                }

                pasteURLSection
            }

            // Cinema services: paste URL only
            if cinemaServices.contains(selectedService) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ссылка на контент")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Cinema2026.secondary)
                    TextField("https://\(selectedService.rawValue).com/...", text: $mediaURL)
                        .font(.system(size: 16))
                        .foregroundStyle(Cinema2026.text)
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Cinema2026.divider, lineWidth: 0.5))
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Cinema2026.amber)
                    Text(selectedService.subscriptionDisclaimer + " Гости смотрят синхронно через Plink.")
                        .font(.caption)
                        .foregroundStyle(Cinema2026.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Cinema2026.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(selectedService.subscriptionDisclaimer)
            }

            // Custom URL / Browser
            if selectedService == .customURL || selectedService == .browser {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Прямая ссылка")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Cinema2026.secondary)
                    TextField("https://example.com/video.mp4", text: $mediaURL)
                        .font(.system(size: 16))
                        .foregroundStyle(Cinema2026.text)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Cinema2026.divider, lineWidth: 0.5))
                    Text("Поддерживается: .mp4, .m3u8, .mp3")
                        .font(.caption)
                        .foregroundStyle(Cinema2026.secondary)
                }
            }

            // Continue button
            Button {
                continueFromContent()
            } label: {
                Text("Продолжить")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Cinema2026.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(canContinueFromContent ? Cinema2026.accent : Cinema2026.surface, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(!canContinueFromContent)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 32)
    }

    private var canContinueFromContent: Bool {
        if selectedService == .youtube {
            return mediaVideoId != nil || !mediaURL.isEmpty
        }
        return !mediaURL.isEmpty
    }

    private var brandCarouselServices: [VideoService] {
        [.kinopoisk, .okko, .youtube, .ivi, .wink, .start, .premier, .rutube, .vk, .kion]
    }

    private var serviceBrandCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Доступно в Plink")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Cinema2026.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(brandCarouselServices, id: \.self) { service in
                        serviceLogoPill(service)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .scrollDisabled(false)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Карусель поддерживаемых сервисов")
    }

    private func serviceLogoPill(_ service: VideoService) -> some View {
        HStack(spacing: 9) {
            ServiceLogoView(service: service, size: 28)
                .frame(width: 28, height: 28)

            Text(service.brandName)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Cinema2026.text)
                .lineLimit(1)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 46)
        .background(
            LinearGradient(
                colors: [
                    service.accentColor.opacity(0.26),
                    Cinema2026.surface.opacity(0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(service.accentColor.opacity(0.24), lineWidth: 0.8)
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var pasteURLSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Или вставьте ссылку")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Cinema2026.secondary)
            TextField("https://...", text: $mediaURL)
                .font(.system(size: 16))
                .foregroundStyle(Cinema2026.text)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Cinema2026.divider, lineWidth: 0.5))
        }
    }

    // MARK: - Step 3: Settings

    private var settingsStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("НАСТРОЙКИ")
                .font(.caption2.bold())
                .tracking(1.1)
                .foregroundStyle(Cinema2026.accent)
            Text("Финальный штрих")
                .font(.largeTitle.bold())
                .foregroundStyle(Cinema2026.text)

            // Content preview
            if !mediaTitle.isEmpty || mediaThumbnail != nil {
                HStack(spacing: 12) {
                    if let thumb = mediaThumbnail, let url = URL(string: thumb) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(Cinema2026.surface)
                        }
                        .frame(width: 80, height: 45)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: selectedService.icon)
                            .font(.system(size: 24))
                            .foregroundStyle(selectedService.accentColor)
                            .frame(width: 80, height: 45)
                            .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mediaTitle.isEmpty ? selectedService.title : mediaTitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Cinema2026.text)
                            .lineLimit(2)
                        Text(selectedService.title)
                            .font(.system(size: 12))
                            .foregroundStyle(Cinema2026.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Cinema2026.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }

            // Room name
            VStack(alignment: .leading, spacing: 8) {
                Text("Название комнаты")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Cinema2026.secondary)
                TextField("Комната друзей", text: $roomName)
                    .font(.system(size: 16))
                    .foregroundStyle(Cinema2026.text)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Cinema2026.divider, lineWidth: 0.5))
            }

            if let friend = inviteFriend {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(Cinema2026.accent)
                    Text("После создания \(friend.displayTitle) получит приглашение в чат")
                        .font(.caption)
                        .foregroundStyle(Cinema2026.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Cinema2026.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            // Privacy
            VStack(alignment: .leading, spacing: 8) {
                Text("Приватность")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Cinema2026.secondary)
                HStack(spacing: 10) {
                    privacyChip("Публичная", privacy == .publicRoom) { privacy = .publicRoom }
                    privacyChip("Приватная", privacy == .privateRoom) { privacy = .privateRoom }
                }
            }

            // Max participants
            VStack(alignment: .leading, spacing: 8) {
                Text("Максимум участников: \(maxParticipants)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Cinema2026.secondary)
                Stepper(value: $maxParticipants, in: 2...(isPremium ? 50 : 4)) {
                    Text("\(maxParticipants) чел.")
                        .font(.system(size: 14))
                        .foregroundStyle(Cinema2026.text)
                }
                .tint(Cinema2026.accent)
                if !isPremium {
                    Text("Plink+ — до 50 участников")
                        .font(.caption)
                        .foregroundStyle(Cinema2026.amber)
                }
            }

            // Error
            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Cinema2026.danger)
                    .padding(12)
                    .background(Cinema2026.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            // Create button — always enabled (empty name → auto default)
            Button {
                Task { await createRoom() }
            } label: {
                HStack {
                    if isCreating { ProgressView().tint(Cinema2026.background) }
                    Text(inviteFriend == nil ? "Создать комнату" : "Создать и пригласить")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Cinema2026.background)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(isCreating ? Cinema2026.surface : Cinema2026.accent, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(isCreating)
            .onAppear {
                fillDefaultRoomName()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 32)
    }

    private func privacyChip(_ title: String, _ isSelected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? Cinema2026.background : Cinema2026.text)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(isSelected ? Cinema2026.accent : Cinema2026.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 4: Creating

    private var creatingStep: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Cinema2026.accent)
            Text("Создаём комнату…")
                .font(.headline)
                .foregroundStyle(Cinema2026.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Create

    private func requiresSmartWall(for service: VideoService) -> Bool {
        !WatchRoomModel.checkServiceAccess(for: service.serviceType)
    }

    @discardableResult
    private func ensureServiceAccess(for service: VideoService, pending action: PendingAuthAction) -> Bool {
        guard requiresSmartWall(for: service) else { return true }
        pendingAuthAction = action
        authWallService = service
        return false
    }

    private func resumePendingAuthAction() {
        guard let action = pendingAuthAction else { return }
        pendingAuthAction = nil
        switch action {
        case .continueToSettings:
            continueFromContent(skipAuth: true)
        case .fastYouTube(let videoId, let title, let thumbnail):
            beginFastYouTubeCreate(videoId: videoId, title: title, thumbnail: thumbnail, skipAuth: true)
        case .createRoom:
            Task { await createRoom(skipAuth: true) }
        }
    }

    private func continueFromContent(skipAuth: Bool = false) {
        if mediaTitle.isEmpty {
            mediaTitle = selectedService.title
        }
        fillDefaultRoomName()
        guard skipAuth || ensureServiceAccess(for: selectedService, pending: .continueToSettings) else { return }
        step = .settings
    }

    private func beginFastYouTubeCreate(videoId: String, title: String, thumbnail: String?, skipAuth: Bool = false) {
        guard isValidYouTubeVideoId(videoId) else {
            errorMessage = "Не удалось распознать YouTube-видео. Попробуйте другое."
            showYouTubeSearch = false
            step = .content
            return
        }

        selectedService = .youtube
        mediaVideoId = videoId
        mediaURL = "https://www.youtube.com/watch?v=\(videoId)"
        mediaTitle = title
        mediaThumbnail = thumbnail
        fillDefaultRoomName(preferredTitle: title)
        showYouTubeSearch = false
        errorMessage = nil

        guard skipAuth || ensureServiceAccess(
            for: selectedService,
            pending: .fastYouTube(videoId: videoId, title: title, thumbnail: thumbnail)
        ) else { return }

        step = .creating
        Task { await createRoom(skipAuth: true) }
    }

    private func fillDefaultRoomName(preferredTitle: String? = nil) {
        guard roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let friend = inviteFriend {
            roomName = "С \(friend.displayTitle)"
        } else if let preferredTitle, !preferredTitle.isEmpty {
            roomName = String(preferredTitle.prefix(40))
        } else if !mediaTitle.isEmpty {
            roomName = String(mediaTitle.prefix(40))
        } else {
            roomName = selectedService.title
        }
    }

    private func createRoom(skipAuth: Bool = false) async {
        guard skipAuth || ensureServiceAccess(for: selectedService, pending: .createRoom) else { return }
        // P0.2: idempotency guard — prevent double-tap creating two rooms
        guard !isCreating else { return }
        isCreating = true
        errorMessage = nil
        step = .creating
        defer { isCreating = false }

        // Ensure JWT is on the API client used by this sheet (shared or injected)
        AuthService.shared.rebindSessionFromStorage()
        if apiClient.authToken == nil {
            apiClient.authToken = AuthService.shared.authToken
                ?? KeychainHelper.read(for: "rave_auth_token")
        }
        if APIClient.shared.authToken == nil {
            APIClient.shared.authToken = apiClient.authToken
        }
        guard apiClient.authToken != nil else {
            errorMessage = "Сессия истекла. Выйдите и войдите снова."
            step = .settings
            return
        }

        // Build MediaItem based on service
        let mediaItem: MediaItem
        let streamURL: String
        let source: MediaItem.MediaSource
        let videoId: String?

        switch selectedService {
        case .youtube:
            guard let vid = mediaVideoId ?? extractYouTubeId(from: mediaURL), isValidYouTubeVideoId(vid) else {
                errorMessage = "Вставьте корректную ссылку YouTube или выберите видео из поиска."
                step = .content
                return
            }
            // Prefer watch URL — more reliable for id extract + backend
            streamURL = "https://www.youtube.com/watch?v=\(vid)"
            videoId = vid
            source = .youtube
        case .vk:
            streamURL = mediaURL
            videoId = nil
            source = .url
        case .rutube:
            streamURL = mediaURL.trimmingCharacters(in: .whitespacesAndNewlines)
            videoId = nil
            source = .url
        case .customURL:
            streamURL = mediaURL
            videoId = nil
            source = .url
        case .browser:
            streamURL = mediaURL
            videoId = nil
            source = .url
        default:
            // Cinema services
            streamURL = mediaURL
            videoId = nil
            source = .url
        }

        mediaItem = MediaItem(
            id: streamURL,
            title: mediaTitle.isEmpty ? selectedService.title : mediaTitle,
            artist: nil,
            thumbnailURL: mediaThumbnail,
            streamURL: streamURL,
            duration: nil,
            mediaType: .video,
            source: source,
            videoId: videoId
        )

        let hostName = AuthService.shared.currentUserValue?.username
            ?? UserDefaults.standard.string(forKey: "plink_current_username")

        // Guard empty URL for link-based services
        if selectedService == .rutube || selectedService == .vk || selectedService == .customURL || selectedService == .browser {
            let trimmed = mediaURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || !trimmed.lowercased().hasPrefix("http") {
                errorMessage = "Вставьте корректную ссылку (https://…)"
                step = .content
                return
            }
        }

        let finalName: String = {
            let t = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
            if let friend = inviteFriend { return "С \(friend.displayTitle)" }
            if !mediaTitle.isEmpty { return String(mediaTitle.prefix(40)) }
            return selectedService.title
        }()

        let request = CreateRoomRequest(
            name: finalName,
            maxParticipants: maxParticipants,
            mediaItem: mediaItem,
            privacy: privacy,
            password: nil,
            hostName: hostName
        )

        do {
            var room = try await RoomService(api: apiClient).createRoom(request)
            // Ensure host is joined (presence / participant count) even if
            // older backends omitted RoomParticipant on create.
            if let joined = try? await RoomService(api: apiClient).joinRoom(code: room.code) {
                // Never drop local mediaItem when join returns a stripped payload
                let mergedMedia = joined.mediaItem ?? room.mediaItem ?? mediaItem
                room = Room(
                    id: joined.id,
                    name: joined.name,
                    hostID: joined.hostID,
                    hostName: joined.hostName,
                    code: joined.code,
                    participants: joined.participants.isEmpty ? room.participants : joined.participants,
                    mediaItem: mergedMedia,
                    isActive: joined.isActive,
                    maxParticipants: joined.maxParticipants,
                    hostIsPremium: joined.hostIsPremium,
                    createdAt: joined.createdAt,
                    privacy: joined.privacy,
                    password: joined.password
                )
            }
            // Keep client-side media if server stripped it
            if room.mediaItem == nil {
                room = Room(
                    id: room.id,
                    name: room.name,
                    hostID: room.hostID,
                    hostName: room.hostName,
                    code: room.code,
                    participants: room.participants,
                    mediaItem: mediaItem,
                    isActive: room.isActive,
                    maxParticipants: room.maxParticipants,
                    hostIsPremium: room.hostIsPremium,
                    createdAt: room.createdAt,
                    privacy: room.privacy,
                    password: room.password
                )
            }
            onRoomCreated(room)
            dismiss()
        } catch {
            let msg = error.localizedDescription
            if msg.lowercased().contains("unauthorized")
                || msg.lowercased().contains("401")
                || msg.localizedCaseInsensitiveContains("вход") {
                errorMessage = "Сессия истекла. Закройте приложение и войдите снова."
            } else if msg.contains("FREE_TIER")
                || msg.localizedCaseInsensitiveContains("1 active room")
                || msg.localizedCaseInsensitiveContains("free tier")
                || msg.contains("403") {
                // Retry once: end own active rooms then create again
                if await endMyActiveRooms() {
                    do {
                        var room = try await RoomService(api: apiClient).createRoom(request)
                        if let joined = try? await RoomService(api: apiClient).joinRoom(code: room.code) {
                            room = joined
                        }
                        if room.mediaItem == nil {
                            room = Room(
                                id: room.id, name: room.name, hostID: room.hostID,
                                hostName: room.hostName, code: room.code,
                                participants: room.participants, mediaItem: mediaItem,
                                isActive: room.isActive, maxParticipants: room.maxParticipants,
                                hostIsPremium: room.hostIsPremium, createdAt: room.createdAt,
                                privacy: room.privacy, password: room.password
                            )
                        }
                        onRoomCreated(room)
                        dismiss()
                        return
                    } catch {
                        errorMessage = "Не удалось создать комнату. Попробуйте ещё раз."
                    }
                } else {
                    errorMessage = "Уже есть активная комната. Закройте её и создайте новую."
                }
            } else {
                errorMessage = "Не удалось создать комнату: \(msg)"
            }
            step = .settings
        }
    }

    /// Close free-tier leftover rooms so a new create can succeed.
    private func endMyActiveRooms() async -> Bool {
        do {
            let mine = try await RoomService(api: apiClient).fetchMyRooms()
            let active = mine.filter(\.isActive)
            guard !active.isEmpty else { return true }
            for room in active {
                try? await RoomService(api: apiClient).leaveRoom(roomID: room.id)
                try? await RoomService(api: apiClient).deleteRoom(roomID: room.id)
            }
            return true
        } catch {
            return false
        }
    }

    private func extractYouTubeId(from url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidYouTubeVideoId(trimmed) { return trimmed }

        if let components = URLComponents(string: trimmed),
           let videoId = components.queryItems?.first(where: { $0.name == "v" })?.value,
           isValidYouTubeVideoId(videoId) {
            return videoId
        }

        let lower = trimmed.lowercased()
        for marker in ["youtu.be/", "embed/", "shorts/", "live/", "v/"] {
            if let range = lower.range(of: marker) {
                let after = trimmed[range.upperBound...]
                let candidate = String(after.split(separator: "?").first ?? Substring(after))
                    .split(separator: "/")
                    .first
                    .map(String.init) ?? ""
                if isValidYouTubeVideoId(candidate) { return candidate }
            }
        }
        return nil
    }

    private func isValidYouTubeVideoId(_ value: String) -> Bool {
        guard value.count == 11 else { return false }
        return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }
}
