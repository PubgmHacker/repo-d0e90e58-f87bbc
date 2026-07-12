// Plink/AppShell/PlinkAppShell.swift — GPT-5.6 V4 Rescue §2
//
// Injects PlinkThemeStore + LivingMotionPolicy at shell root.
// Preserves dependencies, iPad split, room/full-screen presentation.

import SwiftUI

struct PlinkAppShell: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: AppSection = .home
    @State private var createIntent: CreateRoomIntent?
    @State private var createdRoom: Room?

    // GPT-5.6 §2: single theme store + motion policy at shell root
    @State private var themeStore = PlinkThemeStore()
    @State private var motionPolicy = LivingMotionPolicy()

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
                PlinkPhoneTabShell(
                    selection: $selection,
                    createIntent: $createIntent,
                    dependencies: dependencies
                )
            }
            #endif
        }
        .environment(themeStore)
        .environment(motionPolicy)
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
}
