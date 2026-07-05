import SwiftUI

// MARK: - Room Creation Flow v3
/// Шаг 1: ServiceSelectionView (премиальный выбор сервиса)
/// Шаг 2: Настройки комнаты (название, приватность)
/// Шаг 3: Приглашение друзей
struct RoomCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    var friendManager: FriendManager? = nil
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
    @State private var showPaywallForLimit = false

    // 🔧 NEW: RoomSetupView state (for the new flow: Service → Browser → Setup → Room)
    // Используем Optional struct + .fullScreenCover(item:) чтобы передать
    // contentURL напрямую в closure (без race condition с @State).
    @State private var showRoomSetup = false
    @State private var setupService: VideoService = .youtube
    @State private var setupContentURL: String = ""
    @State private var setupContentTitle: String = ""

    // Ошибки валидации
    @State private var nameError: String?
    @State private var urlError: String?

    /// Лимит участников: free=4, premium=50
    private var isPremium: Bool { PremiumStatusManager.shared.isPremium }
    private var maxAllowed: Int { isPremium ? 50 : 4 }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            switch currentStep {
            case .service:
                ServiceSelectionView(
                    onSelect: { service in
                        // Browser / customURL — go straight to details (URL entry)
                        selectedService = service
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            currentStep = .details
                        }
                    },
                    onContentSelected: { service, contentURL, contentTitle in
                        // 🔧 FIX: Устанавливаем @State ДО открытия cover.
                        // Раньше showRoomSetup = true срабатывал сразу, и
                        // fullScreenCover closure захватывала пустые значения
                        // (setupContentURL ещё не успел обновиться).
                        // Теперь: сначала обновляем state, потом в следующем
                        // runloop открываем cover.
                        setupService = service
                        setupContentURL = contentURL
                        setupContentTitle = contentTitle
                        print("🔍 RoomCreationView.onContentSelected: setupContentURL='\(setupContentURL)'")
                        // 🔧 Dispatch в следующий runloop чтобы @State успел
                        // обновиться до того как fullScreenCover создаст RoomSetupView
                        DispatchQueue.main.async {
                            showRoomSetup = true
                        }
                    }
                )

            case .details:
                detailsStep

            case .invite:
                inviteStep
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPaywallForLimit) {
            PaywallView(
                onPurchase: { showPaywallForLimit = false },
                onRestore: { },
                onDismiss: { showPaywallForLimit = false }
            )
        }
        // 🔧 FIX: was .sheet — накапливал окна. Now: .fullScreenCover — заменяет.
        // User: 'вкладки предыдущие должны закрываться иначе создается 10+ окон'.
        .fullScreenCover(isPresented: $showRoomSetup) {
            RoomSetupView(
                service: setupService,
                contentURL: setupContentURL,
                contentTitle: setupContentTitle,
                onRoomCreated: { room in
                    showRoomSetup = false
                    onRoomCreated(room)
                }
            )
        }
    }

    // MARK: - Step 2: Details

    private var detailsStep: some View {
        VStack(spacing: 0) {
            premiumNav(title: "Настройки")

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Выбранный сервис
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(selectedService.accentColor.opacity(0.15))
                                .frame(width: 44, height: 44)
                            ServiceLogoIcon(service: selectedService, size: 24)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedService.brandName)
                                .font(.subheadline.bold())
                                .foregroundColor(.raveTextPrimary)
                            Text(selectedService.subtitle)
                                .font(.caption)
                                .foregroundColor(.raveTextSecondary)
                        }
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                                currentStep = .service
                            }
                        } label: {
                            Text("Изменить")
                                .font(.caption.bold())
                                .foregroundColor(.raveAccent)
                        }
                    }
                    .padding(14)
                    .glassCard(cornerRadius: 16, opacity: 0.06)
                    // Ссылка на контент
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ссылка на \(selectedService.title)")
                            .font(.subheadline.bold())
                            .foregroundColor(.raveTextPrimary)
                        TextField(selectedService.placeholder, text: $mediaURL, axis: .vertical)
                            .textFieldStyle(RaveTextFieldStyle())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .lineLimit(2...4)
                            .onChange(of: mediaURL) { _, _ in urlError = nil }

                        if let urlError {
                            Text(urlError)
                                .font(.caption)
                                .foregroundColor(.raveDanger)
                                .transition(.opacity)
                        }
                    }

                    // Название комнаты
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Название комнаты")
                            .font(.subheadline.bold())
                            .foregroundColor(.raveTextPrimary)
                        TextField("Кино вечером 🍿", text: $roomName)
                            .textFieldStyle(RaveTextFieldStyle())
                            .onChange(of: roomName) { _, _ in nameError = nil }

                        if let nameError {
                            Text(nameError)
                                .font(.caption)
                                .foregroundColor(.raveDanger)
                                .transition(.opacity)
                        }
                    }

                    // Макс. участников (free=4, premium=50)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Максимум участников")
                                .font(.subheadline.bold())
                                .foregroundColor(.raveTextPrimary)
                            Spacer()
                            if !isPremium {
                                Text("FREE: до \(maxAllowed)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.raveWarning)
                            }
                        }
                        HStack {
                            Slider(value: Binding(
                                get: { Double(maxParticipants) },
                                set: { newValue in
                                    let clamped = min(Int(newValue), maxAllowed)
                                    maxParticipants = clamped
                                    // Если пытались выкрутить выше лимита → paywall
                                    if Int(newValue) > maxAllowed {
                                        showPaywallForLimit = true
                                    }
                                }
                            ), in: 2...Double(maxAllowed), step: 1)
                            .tint(.ravePrimary)

                            Text("\(maxParticipants)")
                                .font(.title3.bold().monospacedDigit())
                                .foregroundColor(.ravePrimary)
                                .frame(width: 40)
                        }
                        if !isPremium {
                            Button { showPaywallForLimit = true } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 10))
                                    Text("Premium: до 50 участников")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.raveWarning)
                            }
                        }
                    }

                    // Приватность
                    Text("Кто может присоединиться")
                        .font(.subheadline.bold())
                        .foregroundColor(.raveTextPrimary)
                    ForEach(RoomPrivacy.allCases) { mode in
                        privacyCard(mode)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            bottomBar
        }
    }

    // MARK: - Step 3: Invite

    private var inviteStep: some View {
        VStack(spacing: 0) {
            premiumNav(title: "Приглашения")

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if (friendManager?.friends.isEmpty ?? true) {
                        VStack(spacing: 14) {
                            Image(systemName: "person.2.slash")
                                .font(.system(size: 44))
                                .foregroundColor(.raveTextTertiary)
                            Text("У вас пока нет друзей")
                                .font(.headline)
                                .foregroundColor(.raveTextPrimary)
                            Text("Добавьте друзей, чтобы приглашать их в комнаты")
                                .font(.subheadline)
                                .foregroundColor(.raveTextSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        Text("Выберите друзей (\(selectedFriendIds.count))")
                            .font(.subheadline.bold())
                            .foregroundColor(.raveTextPrimary)

                        ForEach(friendManager?.friends ?? []) { friend in
                            friendRow(friend)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }

            bottomBar
        }
    }

    // MARK: - Premium Nav

    private func premiumNav(title: String) -> some View {
        HStack {
            Button {
                HapticManager.impact(.light)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    currentStep = currentStep.previous ?? .service
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Назад")
                        .font(.subheadline.bold())
                }
                .foregroundColor(.raveTextPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassCard(cornerRadius: 20, opacity: 0.08)
            }

            Spacer()

            Text(title)
                .font(.headline)
                .foregroundColor(.raveTextPrimary)

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.raveTextSecondary)
                    .padding(10)
                    .glassCard(cornerRadius: 20, opacity: 0.08)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Privacy Card

    private func privacyCard(_ mode: RoomPrivacy) -> some View {
        let isSelected = privacy == mode
        return Button {
            HapticManager.impact(.light)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                privacy = mode
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: mode.icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? .white : .ravePrimary)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? AnyShapeStyle(Color.raveGradient) : AnyShapeStyle(Color.ravePrimary.opacity(0.12)))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title)
                        .font(.subheadline.bold())
                        .foregroundColor(.raveTextPrimary)
                    Text(mode.subtitle)
                        .font(.caption)
                        .foregroundColor(.raveTextSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .raveGreen : .raveTextTertiary)
            }
            .padding(14)
            .glassCard(cornerRadius: 16, opacity: 0.05)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.raveGreen.opacity(0.4) : Color.white.opacity(0.06), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(PremiumButtonStyle(glowColor: .clear))
    }

    // MARK: - Friend Row

    private func friendRow(_ friend: Friend) -> some View {
        let isSelected = selectedFriendIds.contains(friend.id)
        return Button {
            HapticManager.impact(.light)
            if isSelected {
                selectedFriendIds.remove(friend.id)
            } else {
                selectedFriendIds.insert(friend.id)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.raveGradient)
                    Text(friend.initials)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.username)
                        .font(.subheadline.bold())
                        .foregroundColor(.raveTextPrimary)
                    Text(friend.isOnline ? "В сети" : "Не в сети")
                        .font(.caption)
                        .foregroundColor(.raveTextSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .raveGreen : .raveTextTertiary)
            }
            .padding(12)
            .glassCard(cornerRadius: 14, opacity: 0.05)
        }
        .buttonStyle(PremiumButtonStyle(glowColor: .clear))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(action: nextStep) {
                HStack {
                    if isCreating { ProgressView().tint(.white) }
                    Text(currentStep == .invite ? "Запустить комнату" : "Далее")
                }
                .font(.headline.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.raveGradient)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(PremiumButtonStyle(glowColor: .ravePrimary))
            .disabled(!canProceed)
            .opacity(canProceed ? 1 : 0.5)
            // 🔧 SUBTLE: glow pulses only when the form is ready to proceed —
            // functional feedback that says "you can tap me now". When disabled, no animation.
            .modifier(ConditionalGlow(
                isActive: canProceed && !isCreating,
                color: Color.ravePrimary,
                minRadius: 6, maxRadius: 14,
                minOpacity: 0.15, maxOpacity: 0.35,
                period: 2.0
            ))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var canProceed: Bool {
        switch currentStep {
        case .service: return true
        case .details:
            // Разрешаем нажать — валидация покажет ошибки
            return true
        case .invite: return true
        }
    }

    private func nextStep() {
        HapticManager.impact(.medium)

        // Валидация на шаге details
        if currentStep == .details {
            let trimmedName = roomName.trimmingCharacters(in: .whitespaces)
            let trimmedURL = mediaURL.trimmingCharacters(in: .whitespaces)

            // Проверка названия
            if trimmedName.isEmpty {
                withAnimation { nameError = "Введите название комнаты" }
                return
            }

            // Проверка ссылки
            if trimmedURL.isEmpty {
                withAnimation { urlError = "Введите ссылку на видео" }
                return
            }
            let lower = trimmedURL.lowercased()
            if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
                withAnimation { urlError = "Некорректная ссылка" }
                return
            }
        }

        if let next = currentStep.next {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                currentStep = next
            }
        } else {
            Task { await createRoom() }
        }
    }

    /// Демо-видео: показывается пока пользователь не введёт свой URL.
    /// Big Buck Bunny — открытый тестовый контент Google. Работает с Ambilight.
    private static let demoStreamURL = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"

    @MainActor
    private func createRoom() async {
        isCreating = true

        // Если URL пустой — подставляем демо-видео, чтобы Ambilight и плеер работали
        let effectiveURL = mediaURL.trimmingCharacters(in: .whitespaces).isEmpty
            ? Self.demoStreamURL
            : mediaURL.trimmingCharacters(in: .whitespaces)

        let isDemo = effectiveURL == Self.demoStreamURL

        let finalMediaItem = MediaItem(
            id: UUID().uuidString,
            title: isDemo ? "Big Buck Bunny (демо)" : (mediaTitle.isEmpty ? effectiveURL : mediaTitle),
            artist: isDemo ? "Blender Foundation" : nil,
            thumbnailURL: nil,
            streamURL: effectiveURL,
            duration: isDemo ? 596 : nil,
            mediaType: .video,
            source: .url
        )

        // 🔧 FIX C8: Resolve real host identity + premium status
        // (was: hardcoded hostID="current_user" and hostIsPremium=false)
        let hostID: String = {
            if let data = UserDefaults.standard.data(forKey: "rave_saved_user"),
               let user = try? JSONDecoder().decode(User.self, from: data) {
                return user.id
            }
            return UUID().uuidString
        }()
        let hostName: String = {
            if let data = UserDefaults.standard.data(forKey: "rave_saved_user"),
               let user = try? JSONDecoder().decode(User.self, from: data) {
                return user.username
            }
            return "You"
        }()
        let hostIsPremium = PremiumStatusManager.shared.isPremium

        let room = Room(
            id: UUID().uuidString,
            name: roomName.trimmingCharacters(in: .whitespaces).isEmpty
                ? (isDemo ? "Комната \(generateRoomCode())" : roomName.trimmingCharacters(in: .whitespaces))
                : roomName.trimmingCharacters(in: .whitespaces),
            hostID: hostID,
            hostName: hostName,
            code: generateRoomCode(),
            participants: [],
            mediaItem: finalMediaItem,
            isActive: true,
            maxParticipants: maxParticipants,
            hostIsPremium: hostIsPremium,
            createdAt: Date()
        )

        isCreating = false
        HapticManager.roomJoined()
        onRoomCreated(room)
    }

    private func generateRoomCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}

// MARK: - Creation Steps
enum CreationStep: String, CaseIterable {
    case service, details, invite

    var next: CreationStep? {
        switch self {
        case .service: return .details
        case .details: return .invite
        case .invite: return nil
        }
    }

    var previous: CreationStep? {
        switch self {
        case .service: return nil
        case .details: return .service
        case .invite: return .details
        }
    }
}
