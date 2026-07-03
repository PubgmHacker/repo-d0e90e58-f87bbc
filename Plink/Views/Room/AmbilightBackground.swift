import SwiftUI
import MetalKit
import CoreImage

// MARK: - Ambilight Background
/// Динамический ambient-фон, который мягко дублирует доминирующие цвета
/// из текущего кадра видео. Эффект «Ambilight» как у Philips TV.
///
/// Архитектура:
/// 1. AmbilightSampler — извлекает 3-5 доминирующих цветов из CVPixelBuffer
///    (CIAreaAverage на GPU, сэмплинг 2 Гц, фон).
/// 2. AmbilightBackground — SwiftUI View, рендерит радиальный gradient
///    через Canvas + blur, анимирует переход цветов.
///
/// Энергоэффективность:
/// - Сэмплинг кадра 2 раза/сек (не 60)
/// - CIAreaAverage на GPU (Core Image pipeline)
/// - При заряде < 30% — отключается (EnergyController)
struct AmbilightBackground: View {
    @StateObject private var sampler = AmbilightSampler.shared
    @State private var displayColors: [Color] = [Color.black, Color(hex: 0x0A0A0A)]

    var body: some View {
        Canvas { context, size in
            // Радиальный gradient из доминирующих цветов
            let rect = CGRect(origin: .zero, size: size)

            if displayColors.count >= 2 {
                // Основной gradient — радиальный от центра
                context.fill(
                    Path(rect),
                    with: .radialGradient(
                        Gradient(colors: displayColors),
                        center: CGPoint(x: 0.5, y: 0.5),
                        startRadius: 0,
                        endRadius: max(size.width, size.height) * 0.7
                    )
                )
            } else {
                context.fill(Path(rect), with: .color(.black))
            }
        }
        .blur(radius: 80)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.5), value: displayColors)
        .onReceive(sampler.$colors) { newColors in
            guard !newColors.isEmpty else { return }
            displayColors = newColors
        }
    }
}

// MARK: - Ambilight Sampler

@MainActor
final class AmbilightSampler: ObservableObject {

    static let shared = AmbilightSampler()

    @Published private(set) var colors: [Color] = []

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var lastSampleTime: CFAbsoluteTime = 0
    private let sampleInterval: CFAbsoluteTime = 0.5  // 2 Гц

    private init() {}

    /// Обрабатывает кадр — извлекает доминирующие цвета.
    /// Вызывается ~60 раз/сек, но реально сэмплит 2 раза/сек.
    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        // Throttle: сэмплинг 2 Гц
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSampleTime >= sampleInterval else { return }
        lastSampleTime = now

        // Проверка энергосбережения
        guard !EnergyController.shared.isLowPower else { return }

        Task.detached(priority: .utility) { [ciContext] in
            let extracted = await Self.extractDominantColors(from: pixelBuffer, context: ciContext)
            await MainActor.run {
                self.colors = extracted
            }
        }
    }

    /// Извлечение доминирующих цветов через Core Image.
    /// Даёт 3 цвета: primary, secondary, accent.
    private static func extractDominantColors(
        from pixelBuffer: CVPixelBuffer,
        context: CIContext
    ) async -> [Color] {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Уменьшаем до 8x8 для быстрого анализа (CIAreaAverage)
        let scaleX = 8.0 / ciImage.extent.width
        let scaleY = 8.0 / ciImage.extent.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Рендерим в CGImage
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return [.black]
        }

        // Извлекаем пиксели и считаем доминирующие цвета
        return extractColors(from: cgImage, count: 3)
    }

    /// Простая квантификация: делит цветовое пространство на бакеты,
    /// выбирает 3 самых частых.
    private static func extractColors(from cgImage: CGImage, count: Int) -> [Color] {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [.black] }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Квантификация: 4 бита на канал → 16³ = 4096 бакетов
        var buckets: [UInt32: Int] = [:]

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                let r = pixelData[offset] >> 4      // старшие 4 бита
                let g = pixelData[offset + 1] >> 4
                let b = pixelData[offset + 2] >> 4
                let key = (UInt32(r) << 8) | (UInt32(g) << 4) | UInt32(b)
                buckets[key, default: 0] += 1
            }
        }

        // Топ-N бакетов → цвета
        let sorted = buckets.sorted { $0.value > $1.value }
        let topColors = sorted.prefix(count).map { (key, _) -> Color in
            let r = CGFloat((key >> 8) & 0xF) / 15.0 * 0.6 + 0.2  // затемняем
            let g = CGFloat((key >> 4) & 0xF) / 15.0 * 0.6 + 0.2
            let b = CGFloat(key & 0xF) / 15.0 * 0.6 + 0.2
            return Color(red: r, green: g, blue: b)
        }

        return topColors.isEmpty ? [.black] : topColors
    }

    /// Статичный fallback: генерирует палитру из одного цвета.
    func setFallbackColor(_ color: Color) {
        colors = [color.opacity(0.8), color.opacity(0.3), .black]
    }
}

// MARK: - Energy Controller

@MainActor
final class EnergyController: ObservableObject {
    static let shared = EnergyController()

    @Published var isLowPower: Bool = false

    private init() {
        updateLowPowerStatus()
        // Слушаем изменения состояния зарядки
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateLowPowerStatus() }
        }
    }

    private func updateLowPowerStatus() {
        isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 3:
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
