// Plink/Views/Room/RoomView.swift — Legacy stub (replaced by WatchRoomScreen)
// This file exists ONLY as a fallback when FeatureFlags.realtimeProtocolV2 == false.
// All legacy extraction/sync/player code has been removed.

import SwiftUI

struct RoomView: View {
    let room: Room

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Legacy mode")
                .font(.headline)
            Text("Enable v2 in Settings to use the new watch room.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
