import SwiftUI
#if os(iOS)
import UIKit
import AVFoundation
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

// MARK: - AppDelegate (orientation lock)
//
// 🔧 FIX v2 (July 2026): user-reported bug — "when watching video in landscape
// and swiping left = tabbar appears, screen auto-rotates to portrait, room closes".
//
// Root cause: RoomView was opened via `navigationDestination(item:)` inside a
// NavigationStack inside a TabView. The iOS edge-swipe gesture (used by
// NavigationStack for "swipe to go back") fires when the user swipes left
// from the screen edge in landscape — popping RoomView, returning to the tab,
// re-showing the tabbar, and triggering RoomView.onDisappear → forcePortrait().
// Result: room closes and screen rotates — exactly what the user reported.
//
// Fix: lock the device orientation at the AppDelegate level while RoomView is
// presented. AppDelegate.orientationLock is set to .landscape or .portrait by
// RoomView (via OrientationManager) and to .allByDefault otherwise. Combined
// with `interactiveDismissDisabled(true)` and `.fullScreenCover` presentation
// (see MainTabView), this completely isolates RoomView from TabView gestures
// and system edge-swipe handling.
#if os(iOS)
final class PlinkAppDelegate: NSObject, UIApplicationDelegate {

    /// Active orientation mask. Defaults to `.all` so the rest of the app
    /// supports all orientations. RoomView sets this to `.portrait` or
    /// `.landscape` via OrientationManager.lockOrientation(_:).
    static var orientationLock: UIInterfaceOrientationMask = .all

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        let lock = PlinkAppDelegate.orientationLock
        print("📱 AppDelegate supportedInterfaceOrientationsFor → \(lock)")
        return lock
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // P1.4 Firebase - optional, only configure if valid GoogleService-Info.plist exists
        #if canImport(FirebaseCore)
        if let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plistData = FileManager.default.contents(atPath: plistPath),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
           let appId = plist["GOOGLE_APP_ID"] as? String,
           !appId.isEmpty,
           appId != "YOUR_GOOGLE_APP_ID"  // placeholder check
        {
            // Valid Firebase config — configure
            FirebaseApp.configure()
            AnalyticsService.firebaseConfigured = true
            print("[Firebase] Configured successfully")
        } else {
            // No valid GoogleService-Info.plist — skip Firebase (no crash)
            print("[Firebase] Skipped — GoogleService-Info.plist is placeholder or missing")
            AnalyticsService.firebaseConfigured = false
        }
        #endif
        AnalyticsService.shared.appOpen()
        // Soft-detect LiveKit so mic UI can appear when ops enable keys
        if let base = URL(string: "https://plink-backend-production-ef31.up.railway.app") {
            Task { await FeatureFlags.refreshLiveKitAvailability(apiBaseURL: base) }
        }
        return true
    }
}
#else
final class PlinkAppDelegate: NSObject {
    static var orientationLock: Int = 0
}
#endif

// MARK: - App Entry Point
/// Конфигурирует dependency injection, прокидывает JWT-токен между сервисами,
/// управляет корневой навигацией + жизненным циклом WebSocket,
/// и обрабатывает Universal Links (deep-linking, Блок 3).
@main
struct PlinkApp: App {

    // 🔧 Wire up AppDelegate so `supportedInterfaceOrientationsFor` is consulted
    // by UIKit. Required for the orientation-lock fix above.
    #if os(iOS)
    @UIApplicationDelegateAdaptor(PlinkAppDelegate.self) private var appDelegate
    #endif

    // MARK: - Service Singletons (app lifetime)

    private let apiClient: APIClient
    private let authService: AuthService
    private let mediaService: MediaService
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
        // 🔧 v56 (Gemini): Configure AVAudioSession at app launch.
        // Tells iOS: "we are a media player, don't kill WebKit/AVPlayer
        // when app goes inactive (Control Center, notification shade)".
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ v56: AVAudioSession config failed: \(error)")
        }
        #endif

        let api = APIClient.shared
        apiClient = api
        authService = AuthService.shared
        mediaService = MediaService()
        roomService = RoomService(api: api)
        // 🔧 FIX C5: Shared authenticated client injected into social layer
        _friendManager = State(initialValue: FriendManager(api: api))
        // 🔧 FIX C4: Shared authenticated client injected into DM layer
        _dmChatService = State(initialValue: DMChatService(api: api))
    }

    // MARK: - Root View

    var body: some Scene {
        WindowGroup {
            // PATCH: new cinematic launch gate
            AuthLaunchGate(
                dependencies: AppDependencies(
                    apiClient: apiClient,
                    authService: authService,
                    roomService: roomService,
                    mediaService: mediaService,
                    friendManager: friendManager,
                    dmChatService: dmChatService
                ),
                onboardingStore: UserDefaultsOnboardingStore()
            )
            .environmentObject(deepLinkRouter)
            .environmentObject(friendManager)
            .environmentObject(dmChatService)
            .environmentObject(apiClient)
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
    }

    // MARK: - Authenticated Content

    @ViewBuilder
    private var authenticatedContent: some View {
        // PATCH Cinematic: use new unified PlinkAppShell instead of MainTabView.
        // PlinkAppShell adapts to iPhone (tab bar), iPad/Mac (sidebar).
        PlinkAppShell(dependencies: AppDependencies(
            apiClient: apiClient,
            authService: authService,
            roomService: roomService,
            mediaService: mediaService,
            friendManager: friendManager,
            dmChatService: dmChatService
        ))
        .environmentObject(deepLinkRouter)
        .environmentObject(friendManager)
        .environmentObject(dmChatService)
        .environmentObject(apiClient)
    }

    // MARK: - Login Content

    // loginContent removed — AuthLaunchGate handles auth flow
    // (uses LoginView2026 from Auth2026 folder)

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
            // 🔧 FIX L10: Fetch real username from server (was: hardcoded "Пользователь").
            Task {
                let username = await fetchUsername(userId: userId)
            await MainActor.run {
                    friendInviteAlert = FriendInviteAlert(userId: userId, username: username)
                    deepLinkRouter.clear()
                }
            }

        case .none:
            break
        }
    }

    /// 🔧 FIX L10: Fetch user display name from server for friend-invite alerts.
    private func fetchUsername(userId: String) async -> String {
        // Try to fetch the user's profile from /api/users/:id
        // Falls back to a generic localized string if the request fails.
        struct UserDTO: Decodable {
            let username: String?
        }
        do {
            let user: UserDTO = try await apiClient.request("users/\(userId)")
            return user.username ?? "Пользователь"
        } catch {
            Logger.api.warn("Failed to fetch username for friend invite: \(error.localizedDescription)")
            return "Пользователь"
        }
    }

    // MARK: - Token Bridge

    /// Прокидывает текущий JWT из AuthService во все сервисы:
    /// - MediaService (Authorization: Bearer на extraction-запросах)
    /// APIClient обновляется внутри AuthService.
    private func bridgeAuthToken() async {
        let token = await authService.getFreshToken()
        await MainActor.run {
            mediaService.setAuthToken(token)
        }
    }

    // MARK: - Auth Check

    /// Проверяет сохранённую сессию. Минимальная задержка Splash (≥0.8s) —
    /// чтобы переход был плавным, а не мигал белым при быстром ответе.
    /// 🔧 Pack v3: Проверяет токен через getFreshToken(), а не просто currentUser.
    /// Раньше: currentUser != nil → показывали приложение → первый API запрос → 401.
    /// Теперь: getFreshToken() возвращает nil если токен истёк и refresh не удался → login screen.
    private func checkAuth() {
        Task { [authService, friendManager] in
            // Проверяем токен (getFreshToken рефрешит если истёк)
        let token = await authService.getFreshToken()
            let user = await authService.currentUser()
            try? await Task.sleep(nanoseconds: 900_000_000)

        await MainActor.run {
                // Токен валиден И пользователь есть → показываем приложение
                if token != nil && user != nil {
                    isSignedIn = true
                    Task {
                        await bridgeAuthToken()
                        await friendManager.loadAll()
                    }
                } else {
                    // Токен истёк/невалиден → очищаем сессию → login screen
                    Task { try? await authService.signOut() }
                    isSignedIn = false
                }
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
            Cinema2026.background.ignoresSafeArea()

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
