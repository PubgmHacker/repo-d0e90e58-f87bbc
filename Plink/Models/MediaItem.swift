import Foundation

// MARK: - Media Item
struct MediaItem: Codable, Identifiable, Sendable, Equatable, Hashable {
    let id: String
    let title: String
    let artist: String?           // For music
    let thumbnailURL: String?
    let streamURL: String         // Direct playable URL
    let duration: TimeInterval?
    let mediaType: MediaType
    let source: MediaSource

    enum MediaType: String, Codable, Sendable {
        case movie = "movie"
        case series = "series"
        case music = "music"
        case video = "video"
        case livestream = "livestream"
    }

    enum MediaSource: String, Codable, Sendable {
        case url = "url"              // Direct URL
        case youtube = "youtube"
        case plex = "plex"
        case jellyfin = "jellyfin"
        case local = "local"
    }

    var displayTitle: String {
        if let artist {
            return "\(artist) — \(title)"
        }
        return title
    }

    var formattedDuration: String? {
        guard let duration else { return nil }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static var preview: MediaItem {
        MediaItem(
            id: "media_001",
            title: "Big Buck Bunny",
            artist: nil,
            thumbnailURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/Big_buck_bunny_poster_big.jpg/800px-Big_buck_bunny_poster_big.jpg",
            streamURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
            duration: 596,
            mediaType: .movie,
            source: .url
        )
    }

    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool {
        lhs.id == rhs.id
    }
}
