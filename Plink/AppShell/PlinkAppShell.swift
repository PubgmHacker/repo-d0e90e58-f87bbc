// Plink/AppShell/PlinkAppShell.swift — §4 Final Architecture
//
// One canonical create presentation via RoomCreationView (not CreateRoomView).
// fullScreenCover for WatchRoom on room creation.

import SwiftUI

struct PlinkAppShell: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: AppSection = .home
    @State private var createPresented = false
    @State private var createdRoom: Room?

    let dependencies: AppDependencies

    var body: some View {
        Group {
            #if os(macOS)
            PlinkSidebarShell(
                selection: $selection,
                createPresented: $createPresented,
                dependencies: dependencies
            )
            #else
            if horizontalSizeClass == .regular {
                PlinkSidebarShell(
                    selection: $selection,
                    createPresented: $createPresented,
                    dependencies: dependencies
                )
            } else {
                PlinkPhoneTabShell(
                    selection: $selection,
                    createPresented: $createPresented,
                    dependencies: dependencies
                )
            }
            #endif
        }
        .sheet(isPresented: $createPresented) {
            RoomCreationView(
                onRoomCreated: { room in
                    createPresented = false
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
