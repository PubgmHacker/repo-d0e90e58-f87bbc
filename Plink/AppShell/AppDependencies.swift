// Plink/AppShell/AppDependencies.swift — Dependency injection container
//
// PLINK_UNIFIED_IOS_MAC_CINEMATIC_PATCH §2: AppDependencies wraps existing services.
// Does NOT create new singletons — just bundles existing ones for the shell.

import Foundation

@MainActor
final class AppDependencies {
    let apiClient: APIClient
    let authService: AuthService
    let roomService: RoomService
    let discoveryService: DiscoveryService
    let premiumStatusManager: PremiumStatusManager

    init(
        apiClient: APIClient,
        authService: AuthService,
        roomService: RoomService,
        discoveryService: DiscoveryService? = nil,
        premiumStatusManager: PremiumStatusManager = .shared
    ) {
        self.apiClient = apiClient
        self.authService = authService
        self.roomService = roomService
        self.discoveryService = discoveryService ?? DiscoveryService(apiClient: apiClient, roomService: roomService)
        self.premiumStatusManager = premiumStatusManager
    }

    /// Live dependencies wired from existing app state.
    static var live: AppDependencies {
        let apiBaseURL = "https://plink-backend-production-ef31.up.railway.app/api"
        let apiClient = APIClient(baseURL: apiBaseURL)
        let authService = AuthService()
        let roomService = RoomService(api: apiClient)
        return AppDependencies(
            apiClient: apiClient,
            authService: authService,
            roomService: roomService
        )
    }
}
