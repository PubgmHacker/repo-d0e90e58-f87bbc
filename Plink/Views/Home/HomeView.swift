import SwiftUI

// MARK: - Toast Message
struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    let icon: String
}

// MARK: - Home View v3 — "Pure Black × Ice Glow"
///
/// Минимализм. Только две горизонтальные секции:
/// 1. «Сейчас в эфире» — live-карточки с индикатором LIVE
/// 2. «Рекомендации для тебя» — постеры фильмов/видео
/// Floating CTA «Создать комнату» внизу. Никаких «общих комнат».
struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @State private var showCreateRoom = false
    @State private var showJoinSheet = false
    @State private var joinInput = ""
    @State private var navigateToRoom: Room?
    @State private var toast: ToastMessage?

    @State private var reportRoomTarget: Room?
    @State private var blockRoomTarget: Room?
    @ObservedObject private var loc = LocalizationManager.shared

    // Каскадная анимация появления
    @State private var appeared = false

    // Кнопка «Создать комнату» — сворачивается в плюсик через 8 сек
    @State private var isCTACollapsed = false
    @State private var ctaCollapseTimer: Timer?
    @State private var userInteracted = false

    // ИИ-помощник
    @State private var aiQuery = ""
    @State private var aiResults: [Room] = []
    @State private var aiSearching = false
    @State private var showProfile = false

    // onProfileTap больше не используется (профиль открывается через sheet).
    // Оставлен для совместимости со старым вызовом из MainTabView.
    var onProfileTap: () -> Void = {}

    init(viewModel: HomeViewModel, onProfileTap: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onProfileTap = onProfileTap
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Чёрный фон + blur-пятна
                AnimatedGradientBackground()

                // Контент
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        headerView
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        // ИИ-помощник «Что посмотреть?»
                        aiAssistantBar
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        // Результаты ИИ
                        if !aiResults.isEmpty {
                            aiResultsSection
                                .padding(.top, 16)
                        }

                        // Секция 1: Сейчас в эфире
                        if !liveRooms.isEmpty {
                            liveSection
                                .padding(.top, 24)
                        }

                        // Секция 2: Рекомендации для тебя
                        recommendationsSection
                            .padding(.top, 28)
                            .padding(.bottom, 120) // место под floating CTA
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    // Тап по контенту сбрасывает таймер сворачивания CTA
                    resetCTACollapseTimer()
                }

                // Floating CTA внизу
                VStack {
                    Spacer()
                    floatingCTA
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
            }
            .navigationDestination(item: $navigateToRoom) { room in
                RoomView(room: room)
            }
            .sheet(isPresented: $showCreateRoom) {
                RoomCreationView { room in
                    showCreateRoom = false
                    navigateToRoom = room
                }
            }
            .sheet(isPresented: $showJoinSheet) {
                joinRoomSheet
            }
            .sheet(isPresented: $showProfile) {
                NavigationStack {
                    ProfileView(
                        viewModel: ProfileViewModel(authService: AuthService(api: APIClient())),
                        onSignOut: { showProfile = false }
                    )
                }
                .preferredColorScheme(.dark)
            }
            .overlay(alignment: .top) {
                if let toast {
                    Label(toast.text, systemImage: toast.icon)
                        .font(.subheadline.bold())
                        .foregroundColor(.raveTextPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassCard(cornerRadius: 14, opacity: 0.08)
                        .padding(.top, 50)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                await MainActor.run { self.toast = nil }
                            }
                        }
                }
            }
            .task { await viewModel.loadRooms() }
            .refreshable { await viewModel.refresh() }
            .alert(loc.string(.reportRoom), isPresented: Binding(
                get: { reportRoomTarget != nil },
                set: { if !$0 { reportRoomTarget = nil } }
            )) {
                Button(loc.string(.cancel), role: .cancel) { reportRoomTarget = nil }
                ForEach(ReportReason.allCases) { reason in
                    Button(reason.rawValue) {
                        if let target = reportRoomTarget {
                            toast = ToastMessage(text: loc.string(.reportRoomSent), icon: "flag.fill")
                            UserBlockManager().reportRoom(target.id, reason: reason.apiCode) { _ in }
                        }
                        reportRoomTarget = nil
                    }
                }
            }
            .alert(loc.string(.blockHost), isPresented: Binding(
                get: { blockRoomTarget != nil },
                set: { if !$0 { blockRoomTarget = nil } }
            )) {
                Button(loc.string(.cancel), role: .cancel) { blockRoomTarget = nil }
                Button(loc.string(.blockHostTitle), role: .destructive) {
                    if let target = blockRoomTarget {
                        viewModel.blockRoom(target)
                        toast = ToastMessage(text: loc.string(.blockHostDone), icon: "hand.raised.fill")
                    }
                    blockRoomTarget = nil
                }
            } message: {
                Text(loc.string(.blockHostMessage))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                appeared = true
            }
            startCTACollapseTimer()
        }
    }

    // MARK: - Header (минимализм: приветствие + аватар)

    private var headerView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Привет 👋")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.raveTextSecondary)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : -8)

                Text(loc.string(.homeDiscover))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(.raveTextPrimary)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : -8)
            }

            Spacer()

            // Аватарка (tap → экран профиля, НЕ настройки)
            Button {
                showProfile = true
            } label: {
                Circle()
                    .fill(Color.raveGlass)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.ravePrimary)
                    )
                    .glassCard(cornerRadius: 22, opacity: 0.06)
            }
            .buttonStyle(PremiumButtonStyle(glowColor: .ravePrimary))

            // Join по коду
            Button {
                showJoinSheet = true
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.raveAccent)
                    .frame(width: 44, height: 44)
                    .glassCard(cornerRadius: 22, opacity: 0.06)
            }
            .buttonStyle(PremiumButtonStyle(glowColor: .raveAccent))
        }
        .opacity(appeared ? 1 : 0)
    }

    // MARK: - Live Section (Сейчас в эфире)

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Заголовок секции
            HStack(spacing: 8) {
                Text(loc.string(.homeWatchingNow))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.raveTextPrimary)
                Spacer()
                Text("\(liveRooms.count)")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundColor(.raveTextSecondary)
            }
            .padding(.horizontal, 20)

            // Горизонтальный скролл live-карточек
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(liveRooms) { room in
                        Button {
                            HapticManager.impact(.light)
                            navigateToRoom = room
                        } label: {
                            LiveCardView(room: room)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
    }

    // MARK: - Recommendations Section (Рекомендации для тебя)

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Рекомендации для тебя")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.raveTextPrimary)
                Spacer()
            }
            .padding(.horizontal, 20)

            // Если сервер пустой — показываем мок-рекомендации
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(recommendationRooms) { room in
                        Button {
                            HapticManager.impact(.light)
                            navigateToRoom = room
                        } label: {
                            RecommendationCardView(room: room)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 30)
    }

    // MARK: - AI Results Section

    private var aiResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundColor(.ravePrimary)
                Text("Рекомендации ИИ")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.raveTextPrimary)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(aiResults) { room in
                        Button {
                            HapticManager.impact(.light)
                            navigateToRoom = room
                        } label: { RecommendationCardView(room: room) }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - AI Assistant Bar («Что посмотреть?»)

    private var aiAssistantBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.ravePrimary)

            TextField("Что посмотреть?", text: $aiQuery)
                .font(.system(size: 16))
                .foregroundColor(.raveTextPrimary)
                .submitLabel(.search)
                .onSubmit {
                    Task { await searchAI() }
                }

            if aiSearching {
                ProgressView()
                    .tint(.ravePrimary)
                    .scaleEffect(0.8)
            } else if !aiQuery.isEmpty {
                Button { aiQuery = ""; aiResults = [] } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.raveTextSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 14, opacity: 0.05)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.ravePrimary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func searchAI() async {
        let query = aiQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        aiSearching = true
        defer { aiSearching = false }

        // Ищем по реальным комнатам с сервера
        let all = viewModel.filteredRooms
        aiResults = all.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.mediaItem?.title.localizedCaseInsensitiveContains(query) == true
        }

        if aiResults.isEmpty {
            // Если ничего не найдено — показываем доступные комнаты
            aiResults = Array(all.prefix(3))
        }
    }

    // MARK: - Floating CTA (Создать комнату) — плавная анимация морфинга
    //
    // Один и тот же view, у которого плавно меняются: ширина (full → 56),
    // cornerRadius (20 → 28), прозрачность текста (1 → 0).
    // Так SwiftUI анимирует морфинг без cross-fade.

    private var floatingCTA: some View {
        Button {
            HapticManager.impact(.medium)
            if isCTACollapsed {
                // Тап по свёрнутой иконке — ТОЛЬКО разворачивает (без создания комнаты).
                withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                    isCTACollapsed = false
                }
                resetCTACollapseTimer()
            } else {
                // Тап по развёрнутой кнопке — открывает создание комнаты.
                showCreateRoom = true
            }
        } label: {
            ctaLabel
        }
        .buttonStyle(CTAPressStyle())
        // Позиционирование: всегда по центру внизу (не смещается в угол)
        .frame(maxWidth: .infinity, alignment: .center)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 40)
    }

    /// Единый лейбл кнопки — анимируется через интерполяцию параметров.
    private var ctaLabel: some View {
        HStack(spacing: isCTACollapsed ? 0 : 12) {
            // Иконка плюса — всегда видна
            ZStack {
                Circle()
                    .fill(Color.premiumGradient)
                    .frame(width: isCTACollapsed ? 56 : 36,
                           height: isCTACollapsed ? 56 : 36)
                Image(systemName: "plus")
                    .font(.system(size: isCTACollapsed ? 22 : 18, weight: .bold))
                    .foregroundColor(.white)
            }

            // Текст — исчезает при сворачивании (плавная прозрачность + сжатие)
            Group {
                if !isCTACollapsed {
                    Text(loc.string(.homeCreateRoom))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .transition(.opacity)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.raveAccent)
                }
            }
            .opacity(isCTACollapsed ? 0 : 1)
        }
        .padding(.horizontal, isCTACollapsed ? 0 : 20)
        .padding(.vertical, isCTACollapsed ? 0 : 16)
        .frame(
            width: isCTACollapsed ? 56 : nil,
            height: isCTACollapsed ? 56 : nil
        )
        .background(
            ZStack {
                if isCTACollapsed {
                    // Свёрнутая — только круг
                    Circle()
                        .fill(Color.premiumGradient)
                } else {
                    // Развёрнутая — чёрная плашка
                    Color.black.opacity(0.8)
                }
            }
        )
        // Скругление: 28 для круга (56/2), 20 для плашки
        .clipShape(RoundedRectangle(cornerRadius: isCTACollapsed ? 28 : 20))
        .overlay(
            // Обводка только в развёрнутом состоянии
            RoundedRectangle(cornerRadius: isCTACollapsed ? 28 : 20)
                .stroke(
                    LinearGradient(
                        colors: isCTACollapsed
                            ? [.clear]
                            : [Color.ravePrimary.opacity(0.8), Color.raveAccent.opacity(0.4)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: isCTACollapsed ? 0 : 1.5
                )
        )
        .shadow(color: .ravePrimary.opacity(0.4), radius: 16, y: 6)
    }

    // MARK: - CTA Collapse Timer (сборос на скролл/тап)

    private func startCTACollapseTimer() {
        ctaCollapseTimer?.invalidate()
        ctaCollapseTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                isCTACollapsed = true
            }
        }
    }

    private func resetCTACollapseTimer() {
        ctaCollapseTimer?.invalidate()
        // Если была свёрнута — разворачиваем
        if isCTACollapsed {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                isCTACollapsed = false
            }
        }
        startCTACollapseTimer()
    }

    // MARK: - Data

    /// Live-комнаты: только реальные данные с сервера
    private var liveRooms: [Room] {
        viewModel.filteredRooms.filter { $0.isActive }
            .sorted { $0.participantCount > $1.participantCount }
    }

    /// Рекомендации: реальные комнаты с сервера
    private var recommendationRooms: [Room] {
        viewModel.filteredRooms.sorted { $0.participantCount > $1.participantCount }
    }

    // MARK: - Join Room Sheet

    private var joinRoomSheet: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.raveGradient)
                Text(loc.string(.joinTitle))
                    .font(.title2.bold())
                    .foregroundColor(.raveTextPrimary)
                Text(loc.string(.joinSubtitle))
                    .font(.subheadline)
                    .foregroundColor(.raveTextSecondary)
            }

            TextField("ABC123 или https://...", text: $joinInput)
                .textFieldStyle(RaveTextFieldStyle())
                .multilineTextAlignment(.center)
                .font(.title2.monospaced().bold())
                .padding(.horizontal, 40)
                .autocapitalization(.allCharacters)
                .onChange(of: joinInput) { _, newValue in
                    if !newValue.contains("http") && !newValue.contains(".") {
                        joinInput = String(newValue.prefix(6)).uppercased()
                    } else {
                        joinInput = String(newValue.prefix(500))
                    }
                }

            Button(action: {
                Task {
                    let code = extractCode(from: joinInput)
                    guard !code.isEmpty else { return }
                    do {
                        let room = try await viewModel.joinRoom(code: code)
                        showJoinSheet = false
                        navigateToRoom = room
                        joinInput = ""
                    } catch {
                        viewModel.errorMessage = error.localizedDescription
                    }
                }
            }) {
                Text(loc.string(.joinEnter))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PremiumButtonStyle())
            .background(Color.raveGradient)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .disabled(!isValidJoinInput || viewModel.isLoading)
            .padding(.horizontal, 40)

            if let error = viewModel.errorMessage {
                Text(error).font(.caption).foregroundColor(.raveDanger)
            }

            Button(loc.string(.cancel)) {
                showJoinSheet = false
                joinInput = ""
            }
            .foregroundColor(.raveTextSecondary)

            Spacer()
        }
        .padding(.top, 32)
        .presentationDetents([.medium])
        .presentationBackground(Color.raveBackground)
        .preferredColorScheme(.dark)
    }

    private var isValidJoinInput: Bool {
        let trimmed = joinInput.trimmingCharacters(in: .whitespaces)
        return trimmed.count == 6 || trimmed.contains("http") || trimmed.contains("plnk") || trimmed.contains(".")
    }

    private func extractCode(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if trimmed.count == 6 && trimmed.allSatisfy({ $0.isLetter || $0.isNumber }) { return trimmed }
        if let url = URL(string: trimmed) {
            if let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value { return code }
            let path = url.lastPathComponent
            if path.count >= 4 && path.count <= 8 { return path.uppercased() }
        }
        return trimmed
    }
}

// MARK: - Live Card View (Яндекс Музыка стиль)
///
/// Широкая горизонтальная карточка для live-трансляций.
/// Глубокий чёрный фон, тонкая обводка 0.5pt, glow на постере.
private struct LiveCardView: View {
    let room: Room
    @State private var pulse = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Постер — глубокий чёрный с градиентным переливом
            ZStack(alignment: .topLeading) {
                // Глубокий чёрный фон
                Color(hex: 0x0A0A0A)
                    .frame(width: 260, height: 150)

                // Градиентный перелив постера (Яндекс Музыка стиль)
                LinearGradient(
                    colors: [
                        Color(hex: 0xFF6B35).opacity(isHovered ? 0.5 : 0.3),
                        Color(hex: 0xFF3D8B).opacity(isHovered ? 0.4 : 0.2),
                        Color(hex: 0xE8B339).opacity(isHovered ? 0.35 : 0.15),
                        .black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: 260, height: 150)

                // Glow эффект на постере
                LinearGradient(
                    colors: [.clear, Color(hex: 0xFF6B35).opacity(0.15)],
                    startPoint: .top,
                    endPoint: .center
                )
                .frame(width: 260, height: 75)

                // Иконка play по центру
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(isHovered ? 0.9 : 0.6))
                    .shadow(color: .black.opacity(0.5), radius: 4)

                // LIVE бейдж с пульсацией
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.raveDanger)
                        .frame(width: 6, height: 6)
                        .scaleEffect(pulse ? 1.3 : 1.0)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.raveDanger.opacity(0.25))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.raveDanger.opacity(0.5), lineWidth: 0.5))
                .shadow(color: .raveDanger.opacity(0.4), radius: pulse ? 8 : 3)
                .padding(10)

                // Иконка сервиса
                if let media = room.mediaItem {
                    ServiceBadge(service: media.source == .youtube ? .youtube : .vk, size: 22)
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(width: 260, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )

            // Информация под постером
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.raveTextPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11))
                    Text("\(room.participantCount) смотрят")
                        .font(.system(size: 12))
                }
                .foregroundColor(.raveTextSecondary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
        }
        .frame(width: 260)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Recommendation Card View (Яндекс Музыка стиль)
///
/// Вертикальный постер фильма/видео для секции рекомендаций.
/// Глубокий чёрный фон, тонкая обводка 0.5pt, лёгкое свечение.
private struct RecommendationCardView: View {
    let room: Room
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Постер — глубокий чёрный с градиентным переливом
            ZStack {
                // Глубокий чёрный фон
                Color(hex: 0x0A0A0A)

                // Градиентный перелив (тёплые тона для активных комнат)
                LinearGradient(
                    colors: [
                        gradientColors[0],
                        gradientColors[1],
                        .black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Лёгкое свечение сверху
                LinearGradient(
                    colors: [.clear, gradientColors[0].opacity(isHovered ? 0.2 : 0.1)],
                    startPoint: .top,
                    endPoint: .center
                )

                // Иконка сервиса
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(isHovered ? 0.9 : 0.6))
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
            .frame(width: 150, height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )

            // Название
            Text(room.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.raveTextPrimary)
                .lineLimit(2)
                .frame(width: 150, alignment: .leading)

            // Хост
            Text(room.hostName)
                .font(.system(size: 11))
                .foregroundColor(.raveTextSecondary)
                .lineLimit(1)
        }
        .frame(width: 150)
    }

    private var gradientColors: [Color] {
        // Тёплые тона: оранжевый, розовый, золотой (Яндекс Музыка стиль)
        let palettes: [[Color]] = [
            [Color(hex: 0xFF6B35).opacity(0.4), Color(hex: 0xFF3D8B).opacity(0.2), .black],
            [Color(hex: 0xE8B339).opacity(0.35), Color(hex: 0xFF6B35).opacity(0.2), .black],
            [Color(hex: 0xFF3D8B).opacity(0.3), Color(hex: 0x6EC1E4).opacity(0.2), .black],
            [Color(hex: 0x6EC1E4).opacity(0.3), Color(hex: 0x22D3EE).opacity(0.15), .black],
        ]
        let index = abs(room.id.hashValue) % palettes.count
        return palettes[index]
    }
}

// MARK: - Service Badge (маленькая иконка сервиса)
private struct ServiceBadge: View {
    let service: VideoService
    let size: CGFloat

    var body: some View {
        ServiceLogoIcon(service: service, size: size)
    }
}

// MARK: - CTA Press Style (пружинящая анимация нажатия)
struct CTAPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
