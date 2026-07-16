//
//  WatchRoomContainer.swift
//  Plink
//
//  P0.2b: Unified WatchRoom presentation container.
//  Wraps WatchRoomCompositionRoot.makeScreenForRoom with auth + URL setup.
//

import SwiftUI

struct WatchRoomContainer: View {
    let room: Room
    @Environment(\.dismiss) private var dismiss

    private var authToken: String? {
        AuthService.shared.authToken ?? KeychainHelper.read(for: "rave_auth_token")
    }

    private var userId: String? {
        AuthService.shared.currentUserValue?.id
    }

    private var username: String {
        AuthService.shared.currentUserValue?.username ?? "user"
    }

    var body: some View {
        if let userId, let token = authToken {
            WatchRoomCompositionRoot.makeScreenForRoom(
                room: room,
                userId: userId,
                username: username,
                apiBaseURL: URL(string: "https://plink-backend-production-ef31.up.railway.app")!,
                wsBaseURL: URL(string: "wss://plink-backend-production-ef31.up.railway.app/ws")!,
                authToken: token
            )
            .onAppear {
                if APIClient.shared.authToken == nil {
                    APIClient.shared.authToken = token
                }
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Cinema2026.danger)
                Text("Необходим вход")
                    .font(.headline)
                    .foregroundStyle(Cinema2026.text)
                Button("Закрыть") { dismiss() }
                    .font(.subheadline.bold())
                    .foregroundStyle(Cinema2026.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Cinema2026.background.ignoresSafeArea())
        }
    }
}
