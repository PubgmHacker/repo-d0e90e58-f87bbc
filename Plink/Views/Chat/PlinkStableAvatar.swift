import SwiftUI
import UIKit

// MARK: - Stable avatar (no flicker on poll / historyEpoch)

/// Loads remote avatar once into memory and keeps it — avoids AsyncImage
/// flashing letter ↔ photo every few seconds when chat re-renders.
struct PlinkStableAvatar: View {
    let url: URL?
    let letter: String
    var size: CGFloat = 28

    @State private var image: UIImage?
    @State private var loadedKey: String?

    var body: some View {
        ZStack {
            letterView
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: url?.absoluteString ?? letter) {
            await loadIfNeeded()
        }
    }

    private var letterView: some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [Cinema2026.accent.opacity(0.75), Color.purple.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Text(letter)
                .font(.system(size: max(10, size * 0.38), weight: .bold))
                .foregroundColor(.white)
        }
    }

    @MainActor
    private func loadIfNeeded() async {
        let key = url?.absoluteString ?? ""
        // Already have this URL
        if key == loadedKey, image != nil { return }
        guard let url, !key.isEmpty else {
            image = nil
            loadedKey = nil
            return
        }
        // Memory cache
        if let cached = PlinkAvatarImageCache.shared.image(for: key) {
            image = cached
            loadedKey = key
            return
        }
        do {
            var req = URLRequest(url: url)
            req.cachePolicy = .returnCacheDataElseLoad
            req.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return
            }
            guard let ui = UIImage(data: data) else { return }
            PlinkAvatarImageCache.shared.store(ui, for: key)
            // Only apply if still the same URL
            if url.absoluteString == key {
                image = ui
                loadedKey = key
            }
        } catch {
            // Keep letter fallback — do not thrash
        }
    }
}

@MainActor
final class PlinkAvatarImageCache {
    static let shared = PlinkAvatarImageCache()
    private var map: [String: UIImage] = [:]
    private let maxEntries = 80

    func image(for key: String) -> UIImage? { map[key] }

    func store(_ image: UIImage, for key: String) {
        if map.count >= maxEntries, let first = map.keys.first {
            map.removeValue(forKey: first)
        }
        map[key] = image
    }
}
