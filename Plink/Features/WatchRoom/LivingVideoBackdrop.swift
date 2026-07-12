import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

// LivingVideoBackdrop — captures frames from AVPlayer in real-time,
// applies heavy gaussian blur, and displays as chat background.
// This is the "Rave effect" — chat background breathes with the video.
//
// Implementation:
// 1. AVPlayerItemVideoOutput extracts current frame every 500ms
// 2. CIFilter gaussian blur (radius 40) + vibrance boost
// 3. Display via UIImageView ( bridged to SwiftUI)
// 4. Metal-optimized, never blocks main thread
// 5. Fallback: animated gradient when no video playing

struct LivingVideoBackdrop: View {
    let player: AVPlayer?
    let fallbackColors: [Color]

    init(player: AVPlayer?, fallbackColors: [Color] = [Cinema2026.accent, Cinema2026.surface]) {
        self.player = player
        self.fallbackColors = fallbackColors
    }

    var body: some View {
        ZStack {
            if let player = player, player.currentItem != nil {
                LivingVideoFrameView(player: player)
            } else {
                // PATCH 18 (P1-72): use BioluminescentBackground with .rave
                // palette directly — preserves purple neon design instead
                // of falling back to cyan/teal.
                BioluminescentBackground(energy: 0.5, dimming: 0, palette: .rave)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - Frame capture view

struct LivingVideoFrameView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> LivingVideoFrameUIView {
        let view = LivingVideoFrameUIView()
        view.configure(player: player)
        return view
    }

    func updateUIView(_ uiView: LivingVideoFrameUIView, context: Context) {
        uiView.updatePlayer(player)
    }

    static func dismantleUIView(_ uiView: LivingVideoFrameUIView, coordinator: ()) {
        uiView.cleanup()
    }
}

// MARK: - UIKit frame capture + blur

final class LivingVideoFrameUIView: UIView {
    private var player: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var ciContext: CIContext?
    private let imageView = UIImageView()
    private var lastCaptureTime: CFTimeInterval = 0
    private let captureInterval: CFTimeInterval = 0.5 // 500ms

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = Cinema2026.background.uiColor
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        ciContext = CIContext(options: [.useSoftwareRenderer: false])
    }

    func configure(player: AVPlayer) {
        self.player = player
        setupVideoOutput()
        startDisplayLink()
    }

    func updatePlayer(_ player: AVPlayer) {
        guard self.player !== player else { return }
        cleanup()
        self.player = player
        setupVideoOutput()
        startDisplayLink()
    }

    private func setupVideoOutput() {
        guard let item = player?.currentItem else { return }
        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput = AVPlayerItemVideoOutput(outputSettings: settings)
        item.add(videoOutput!)
    }

    private func startDisplayLink() {
        displayLink?.invalidate()
        displayLink = CADisplayLink(target: self, selector: #selector(captureFrame))
        displayLink?.preferredFramesPerSecond = 2 // ~30fps, but we only capture every 500ms
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func captureFrame() {
        guard let output = videoOutput,
              let item = player?.currentItem,
              item.status == .readyToPlay else { return }

        let now = CACurrentMediaTime()
        guard now - lastCaptureTime >= captureInterval else { return }
        lastCaptureTime = now

        let time = item.currentTime()
        guard output.hasNewPixelBuffer(forItemTime: time) else { return }

        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }

        processFrame(pixelBuffer)
    }

    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let ciContext = ciContext else { return }

        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let blurRadius: Double = 40
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = ciImage
        blur.radius = Float(blurRadius)
        if let blurred = blur.outputImage {
            // Crop to original size (blur expands bounds)
            ciImage = blurred.clamped(to: ciImage.extent).cropped(to: ciImage.extent)
        }

        // Add slight vibrance/saturation boost
        let vibrance = CIFilter.vibrance()
        vibrance.inputImage = ciImage
        vibrance.amount = 0.3
        if let vibrant = vibrance.outputImage {
            ciImage = vibrant
        }

        // Add brightness reduction for chat readability
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = ciImage
        exposure.ev = -0.5
        if let darkened = exposure.outputImage {
            ciImage = darkened
        }

        // Render to CGImage on background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
            DispatchQueue.main.async {
                if let cgImage = cgImage {
                    UIView.transition(with: self.imageView, duration: 0.5, options: .transitionCrossDissolve) {
                        self.imageView.image = UIImage(cgImage: cgImage)
                    }
                }
            }
        }
    }

    func cleanup() {
        displayLink?.invalidate()
        displayLink = nil
        if let item = player?.currentItem, let output = videoOutput {
            item.remove(output)
        }
        videoOutput = nil
        imageView.image = nil
    }

    deinit {
        cleanup()
    }
}

// PATCH 16: AnimatedGradientBackground moved to its own file
// Plink/Views/Components/AnimatedGradientBackground.swift (r2).
// Removed duplicate declaration here.

// MARK: - Color UIColor helper

extension Color {
    var uiColor: UIColor {
        UIColor(self)
    }
}
