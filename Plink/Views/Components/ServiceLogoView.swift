import SwiftUI

// MARK: - ServiceLogoView
/// 🔧 REAL LOGOS: Uses actual brand logos from Assets.xcassets.
/// Logos were downloaded from:
///   - Wikimedia Commons (SVG → PNG) for: YouTube, VK, Netflix, Disney+
///   - Official site favicons (Google S2 favicon API, 128px) for:
///     Rutube, Кинопоиск, Ivi, Okko, Wink, Start, Premier, Smotrim, KION
///
/// Asset names follow the pattern: ServiceLogo{ServiceName}
///   - ServiceLogoYoutube, ServiceLogoVk, ServiceLogoNetflix, etc.
struct ServiceLogoView: View {
    let service: VideoService
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let imageName = service.assetName, let uiImage = UIImage(named: imageName) {
                // Real logo from Assets.xcassets
                Image(uiImage: uiImage)
                    .resizable()
                    .renderingMode(.original)  // preserve brand colors
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                // Fallback: brand-colored circle with initial letter
                fallbackLogo
            }
        }
        .frame(width: size, height: size)
    }

    /// Fallback when asset is missing — uses brand accent color + service initial.
    /// This only shows if the real logo failed to load.
    private var fallbackLogo: some View {
        ZStack {
            Circle()
                .fill(service.accentColor)
                .frame(width: size, height: size)
            Text(String(service.title.prefix(1)).uppercased())
                .font(.system(size: size * 0.5, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

// MARK: - VideoService + Asset Name

extension VideoService {
    /// Asset catalog image name for this service's real logo, or nil if no asset.
    /// Asset names follow the pattern: ServiceLogo{ServiceName}
    var assetName: String? {
        switch self {
        case .youtube:      return "ServiceLogoYoutube"
        case .vk:           return "ServiceLogoVk"
        case .rutube:       return "ServiceLogoRutube"
        case .netflix:      return "ServiceLogoNetflix"
        case .disney:       return "ServiceLogoDisney"
        case .kinopoisk:    return "ServiceLogoKinopoisk"
        case .ivi:          return "ServiceLogoIvi"
        case .okko:         return "ServiceLogoOkko"
        case .wink:         return "ServiceLogoWink"
        case .start:        return "ServiceLogoStart"
        case .premier:      return "ServiceLogoPremier"
        case .smotrim:      return "ServiceLogoSmotrim"
        case .kion:         return "ServiceLogoKion"
        case .browser:      return nil  // uses SF Symbol
        case .customURL:    return nil  // uses SF Symbol
        }
    }
}

// MARK: - Backwards Compatibility Alias
/// 🔧 ServiceLogoIcon is the legacy name used in RoomCreationView, ServiceSelectionView,
/// and HomeView. We alias it to ServiceLogoView so all existing call sites
/// automatically get the real brand logos without source changes.
typealias ServiceLogoIcon = ServiceLogoView
