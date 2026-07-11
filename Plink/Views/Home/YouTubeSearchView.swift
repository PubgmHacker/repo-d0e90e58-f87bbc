// YouTubeSearchView.swift — stub (legacy YouTubeSearchService deleted)
// v2: users paste YouTube URL directly in RoomSetupView
import SwiftUI

struct YouTubeSearchView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("YouTube search temporarily unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
