import Foundation

struct WatchRoomUIState: Equatable {
    var controlsVisible = true
    var chatPresented = false
    var chatDrawerVisible = true
    var isScrubbing = false
    var previewPosition: Double?
    var unreadCount = 0
    var activeToast: RoomToast?
}

struct RoomToast: Identifiable, Equatable {
    enum Kind { case info, success, warning, error }
    let id = UUID()
    let kind: Kind
    let text: String
}
