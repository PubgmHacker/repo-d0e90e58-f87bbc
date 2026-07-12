// Plink/AppShell/PlinkAppShell.swift — §4 Final Architecture + Brain Phase 4
//
// One canonical create presentation via RoomCreationView (not CreateRoomView).
// fullScreenCover for WatchRoom on room creation.
//
// Brain Phase 4: typed CreateRoomIntent replaces Bool createPresented.
// - .chooseService → empty Create flow (persistent button tap)
// - .selectedContent(draft) → RoomCreationView opens RoomSetupView immediately
//   with the draft pre-filled (trending/hero video tap).

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
                PlinkPhoneTabShell(
                    selection: $selection,
                    createIntent: $createIntent,
                    dependencies: dependencies
                )
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
}
