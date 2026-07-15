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

    var body: some View {
        Group {
            if let userId = AuthService.shared.currentUserValue?.id,
               let username = AuthService.shared.currentUserValue?.username,
               let authToken = AuthService.shared.authToken {

                // Debug: log what we received
                let _ = print("[WatchRoom] Room: \(room.id), name: \(room.name)")
                let _ = print("[WatchRoom] mediaItem: \(String(describing: room.mediaItem))")
                if let mi = room.mediaItem {
                    let _ = print("[WatchRoom] videoId: \(mi.videoId ?? "nil"), streamURL: \(mi.streamURL), source: \(mi.source)")
                }

                WatchRoomCompositionRoot.makeScreenForRoom(
                    room: room,
                    userId: userId,
                    username: username,
                    apiBaseURL: URL(string: "https://plink-backend-production-ef31.up.railway.app")!,
                    wsBaseURL: URL(string: "wss://plink-backend-production-ef31.up.railway.app/ws")!,
                    authToken: authToken
                )
            } else {
                // Not authenticated — shouldn't happen, but guard anyway
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
}
