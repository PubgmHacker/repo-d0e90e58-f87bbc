import SwiftUI

// MARK: - App Entry Point
/// Конфигурирует dependency injection, прокидывает JWT-токен между сервисами,
/// управляет корневой навигацией + жизненным циклом WebSocket,
/// и обрабатывает Universal Links (deep-linking, Блок 3).
@main
struct PlinkApp: App {

    // MARK: - Service Singletons (app lifetime)

    private let apiClient: APIClient
    private let authService: AuthService
    private let mediaService: MediaService
    private let wsClient: WebSocketClient
    private let roomService: RoomService

    // Социальный слой (Блок 3)
    // 🔧 FIX C5: Inject shared apiClient into FriendManager (was: own unauth client)
    @State private var friendManager: FriendManager

    // 🔧 FIX C4: Inject shared apiClient into DMChatService (was: own unauth client)
    @State private var dmChatService: DMChatService

    // Deep-linking (Блок 3)
    @StateObject private var deepLinkRouter = DeepLinkRouter()

    // MARK: - State

    /// Состояние запуска: показываем брендовый splash пока проверяем auth.
    @State private var launchPhase: LaunchPhase = .launching

    enum LaunchPhase {
        case launching   // splash виден, идёт проверка auth
        case ready       // проверка завершена — переход к контенту
    }

    @State private var isSignedIn = false
    @State private var showProfile = false
    @State private var showFriends = false
    @State private var showCreateRoom = false
    @State private var deepLinkRoom: Room?
    @State private var friendInviteAlert: FriendInviteAlert?

    // MARK: - Init

    init() {
        let api = APIClient()
        apiClient = api
        authService = AuthService(api: api)
        mediaService = MediaService()
        wsClient = WebSocketClient()
        roomService = RoomService(api: api)
        // 🔧 FIX C5: Shared authenticated client injected into social layer
        _friendManager = State(initialValue: FriendManager(api: api))
        // 🔧 FIX C4: Shared authenticated client injected into DM layer
        _dmChatService = State(initialValue: DMChatService(api: api))
    }

    // MARK: - Root View

    var body: some Scene {
        WindowGroup {
            ZStack {
                // ── Корневой биолюминесцентный фон (виден на всех экранах) ──
                BioluminescentBackground()
                    .ignoresSafeArea()

                if launchPhase == .launching {
                    SplashView()
                        .transition(.opacity)
                } else if isSignedIn {
                    authenticatedContent
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98)),
                            removal: .opacity
                        ))
                } else {
                    loginContent
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98)),
                            removal: .opacity
                        ))
                }
            }
            .animation(.easeInOut(duration: 0.5), value: launchPhase == .ready)
            .animation(.easeInOut(duration: 0.4), value: isSignedIn)
            .onAppear {
                bridgeAuthToken()
                checkAuth()
            }
            // ── Universal Links / Deep-Linking (Блок 3) ───────────────
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
    }

    // MARK: - Authenticated Content

    @ViewBuilder
    private var authenticatedContent: some View {
        MainTabView(authService: authService)
            .environmentObject(deepLinkRouter)
            .environmentObject(friendManager)
            // 🔧 FIX C4+C6: Inject shared services for DM and Admin panels
            .environmentObject(dmChatService)
            .environmentObject(apiClient)
    }

    // MARK: - Login Content

    @ViewBuilder
    private var loginContent: some View {
        NavigationStack {
            LoginView(
                viewModel: AuthViewModel(authService: authService),
                onSignIn: {
                    bridgeAuthToken()   // push jwt to WS + MediaService before entering
                    isSignedIn = true
                    // 🔧 FIX M13: Trigger friends load after sign-in
                    Task { await friendManager.loadAll() }
                }
            )
        }
    }

    // MARK: - Deep-Link Handler (Блок 3)

    /// Обрабатывает входящие Universal Links и custom scheme.
    private func handleDeepLink(_ url: URL) {
        deepLinkRouter.handle(url)

        switch deepLinkRouter.pendingLink {
        case .room(let code):
            // Присоединяемся к комнате по коду из ссылки.
            Task {
                do {
                    let room = try await roomService.joinRoom(code: code)
                    await MainActor.run {
                        deepLinkRoom = room
                        deepLinkRouter.clear()
                    }
                } catch {
                    // Комната не найдена — сбрасываем.
                    await MainActor.run { deepLinkRouter.clear() }
                }
            }

        case .friendInvite(let userId):
            // Показываем красивый алерт с предложением добавить в друзья.
            friendInviteAlert = FriendInviteAlert(userId: userId, username: "Пользователь")
            deepLinkRouter.clear()

        case .none:
            break
        }
    }

    // MARK: - Token Bridge

    /// Прокидывает текущий JWT из AuthService во все сервисы:
    /// - WebSocketClient (?token= + Authorization header)
    /// - MediaService (Authorization: Bearer на extraction-запросах)
    /// APIClient обновляется внутри AuthService.
    private func bridgeAuthToken() {
        Task { [wsClient, mediaService, authService] in
            let token = await authService.getFreshToken()
            await MainActor.run {
                wsClient.setAuthToken(token)
                mediaService.setAuthToken(token)
            }
        }
    }

    // MARK: - Auth Check

    /// Проверяет сохранённую сессию. Минимальная задержка Splash (≥0.8s) —
    /// чтобы переход был плавным, а не мигал белым при быстром ответе.
    private func checkAuth() {
        Task { [authService, friendManager] in
            async let userTask = authService.currentUser()
            async let minDelay: Void = Task { try? await Task.sleep(nanoseconds: 900_000_000); } .value

            let user = await userTask
            _ = await minDelay

            await MainActor.run {
                if user != nil {
                    bridgeAuthToken()
                    isSignedIn = true
                    // 🔧 FIX M13: Trigger friends load AFTER auth token is propagated
                    Task { await friendManager.loadAll() }
                }
                // Плавный уход splash (transition opacity)
                withAnimation(.easeInOut(duration: 0.5)) {
                    launchPhase = .ready
                }
            }
        }
    }
}

// MARK: - Splash View (статичный, чёрный, дорогой)
/// Никакой анимации — биолюминесценция живёт ВНУТРИ приложения.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color.bioObsidian.ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.bioCyan.opacity(0.9), Color.bioEmerald.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: Color.bioCyan.opacity(0.4), radius: 24)

                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundColor(.white)
                }

                Text(LocalizationManager.shared.string(.appName))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                Text(LocalizationManager.shared.string(.appTagline))
                    .font(.subheadline)
                    .foregroundColor(.raveTextSecondary)
            }
        }
    }
}

// MARK: - Friend Invite Alert Model
private struct FriendInviteAlert: Identifiable, Equatable {
    let id = UUID()
    let userId: String
    let username: String

    static func == (lhs: FriendInviteAlert, rhs: FriendInviteAlert) -> Bool {
        lhs.id == rhs.id
    }
}
