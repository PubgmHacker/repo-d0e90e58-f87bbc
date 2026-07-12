// Plink/AppShell/PlinkAppShell.swift — GPT-5.6 V4 Full Replacement
//
// Compact iPhone renders PlinkV4Root with ProductionV4Adapter.
// iPad keeps existing sidebar shell.
// Preserves AuthLaunchGate, deep-link handling, room/watch presentation.

import SwiftUI

struct PlinkAppShell: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: AppSection = .home
    @State private var createIntent: CreateRoomIntent?
    @State private var createdRoom: Room?

    let dependencies: AppDependencies

    var body: some View {
        Group {
            #if os(macOS)
            PlinkSidebarShell(
                selection: $selection,
                createIntent: $createIntent,
                dependencies: dependencies
            )
            #else
            if horizontalSizeClass == .regular {
                PlinkSidebarShell(
                    selection: $selection,
                    createIntent: $createIntent,
                    dependencies: dependencies
                )
            } else {
                // GPT-5.6 V4: iPhone uses PlinkV4Root with adapter
                PlinkV4Root(adapter: makeAdapter())
            }
            #endif
        }
        .sheet(item: $createIntent) { intent in
            RoomCreationView(
                intent: intent,
                onRoomCreated: { room in
                    createIntent = nil
                    createdRoom = room
                }
            )
            .environmentObject(dependencies.apiClient)
        }
        .fullScreenCover(item: $createdRoom) { room in
            WatchRoomCompositionRoot.makeScreenForRoom(
                room: room,
                userId: UserDefaults.standard.string(forKey: "plink_user_id") ?? "",
                username: UserDefaults.standard.string(forKey: "plink_username") ?? "",
                apiBaseURL: URL(string: "https://plink-backend-production-ef31.up.railway.app")!,
                wsBaseURL: URL(string: "wss://plink-backend-production-ef31.up.railway.app/ws")!,
                authToken: KeychainHelper.read(for: "rave_auth_token") ?? ""
            )
        }
    }

    // GPT-5.6 V4: create adapter from existing dependencies
    @MainActor
    private func makeAdapter() -> ProductionV4Adapter {
        ProductionV4Adapter(
            roomService: dependencies.roomService,
            mediaService: dependencies.mediaService,
            friendManager: dependencies.friendManager ?? FriendManager(api: dependencies.apiClient),
            authService: dependencies.authService,
            aiService: PlinkAIService.shared
        )
    }
}
