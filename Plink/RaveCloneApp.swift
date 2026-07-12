import SwiftUI
import UIKit
import AVFoundation

// MARK: - AppDelegate (orientation lock)
//
// Brain Phase 6: orientation lock is consulted by UIKit. WatchRoom sets this
// via OrientationManager; otherwise .all is returned. Combined with
// `interactiveDismissDisabled(true)` and `.fullScreenCover` presentation,
// this isolates WatchRoom from TabView gestures and system edge-swipe handling.
final class PlinkAppDelegate: NSObject, UIApplicationDelegate {

    /// Active orientation mask. Defaults to `.all` so the rest of the app
    /// supports all orientations. WatchRoom sets this to `.portrait` or
    /// `.landscape` via OrientationManager.lockOrientation(_:).
    static var orientationLock: UIInterfaceOrientationMask = .all

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return PlinkAppDelegate.orientationLock
    }
}

// MARK: - App Entry Point
/// Configures dependency injection, exposes JWT token to all services,
/// and handles Universal Links (deep-linking, Block 3).
///
/// Brain Phase 9: removed dead launchPhase / isSignedIn / SplashView /
/// loginContent / authenticatedContent / checkAuth / bridgeAuthToken —
/// AuthLaunchGate now handles the entire launch state machine.
@main
struct PlinkApp: App {

    @UIApplicationDelegateAdaptor(PlinkAppDelegate.self) private var appDelegate

    // MARK: - Service Singletons (app lifetime)

    private let apiClient: APIClient
    private let authService: AuthService
    private let mediaService: MediaService
    private let roomService: RoomService

    @State private var friendManager: FriendManager
    @State private var dmChatService: DMChatService

    @StateObject private var deepLinkRouter = DeepLinkRouter()

    @State private var deepLinkRoom: Room?
    @State private var friendInviteAlert: FriendInviteAlert?

    // MARK: - Init

    init() {
        // Configure AVAudioSession at app launch.
        // Tells iOS: "we are a media player, don't kill WebKit/AVPlayer
        // when app goes inactive (Control Center, notification shade)".
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ AVAudioSession config failed: \(error)")
        }

        let api = APIClient()
        apiClient = api
        authService = AuthService(api: api)
        mediaService = MediaService()
        roomService = RoomService(api: api)
        _friendManager = State(initialValue: FriendManager(api: api))
        _dmChatService = State(initialValue: DMChatService(api: api))
    }

    // MARK: - Root View

    var body: some Scene {
        WindowGroup {
            // Brain Phase 9: AuthLaunchGate handles restoring → auth → onboarding → app.
            // No more launchPhase / isSignedIn / SplashView.
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

    // MARK: - Deep-Link Handler (Block 3)

    /// Handles incoming Universal Links and custom scheme.
    private func handleDeepLink(_ url: URL) {
        deepLinkRouter.handle(url)

        switch deepLinkRouter.pendingLink {
        case .room(let code):
            Task {
                do {
                    let room = try await roomService.joinRoom(code: code)
                    await MainActor.run {
                        deepLinkRoom = room
                        deepLinkRouter.clear()
                    }
                } catch {
                    await MainActor.run { deepLinkRouter.clear() }
                }
            }

        case .friendInvite(let userId):
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

    /// Fetch user display name from server for friend-invite alerts.
    private func fetchUsername(userId: String) async -> String {
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
