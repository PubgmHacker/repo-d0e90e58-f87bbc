// Plink/Features/WatchRoom/WatchRoomSupportTypes.swift — PATCH 02
//
// Slimmed down per PATCH 02 spec. UI views have been extracted to:
//   - PlayerControlLayer.swift  (PlayerTopChrome, PlayerCenterControl,
//                                 PlayerChromeButton, PlayerSmallButton,
//                                 PlayerLoadingView, BufferingOverlay,
//                                 SyncHealthPill)
//   - RoomIdentityBar.swift     (RoomIdentityBar)
//   - WatchRoomOverlays.swift   (RoomToastView, WatchChatSheet,
//                                 LandscapeChatDrawer, WatchChatHeader,
//                                 ChatAvatar, ParticipantAvatar,
//                                 DanmakuCanvasLayer, VoiceActionButton,
//                                 CameraActionButton)
//
// This file keeps only the data types (no View body) that are shared
// across multiple files.

import SwiftUI

// MARK: - Danmaku (flying comments)

struct DanmakuMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let color: Color
    let senderName: String
    let track: Int
    let createdAt: Date
    let isPremium: Bool
    let isAdmin: Bool
}

// MARK: - RTC UI States

enum MicrophoneUIState: Equatable {
    case off
    case on
    case talking
    case pushToTalk
}

enum CameraUIState: Equatable {
    case off
    case on
    case loading
}
