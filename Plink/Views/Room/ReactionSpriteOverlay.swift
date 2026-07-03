import SwiftUI
import SpriteKit

// MARK: - Reaction Sprite Overlay
/// SpriteKit-сцена для анимации реакций (эмодзи) поверх видео.
///
/// Двойной тап по видео → эмодзи вылетает из точки касания и улетает вверх
/// с физикой (гравитация + случайный разброс). GPU-рендеринг = ~0% CPU.
///
/// Используется как overlay поверх видео в RoomView.
struct ReactionSpriteOverlay: UIViewRepresentable {
    @Binding var reactionTrigger: ReactionTrigger?

    func makeUIView(context: Context) -> ReactionSKView {
        let view = ReactionSKView()
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true
        view.backgroundColor = .clear
        let scene = ReactionScene(size: view.bounds.size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        view.presentScene(scene)
        context.coordinator.scene = scene
        return view
    }

    func updateUIView(_ uiView: ReactionSKView, context: Context) {
        guard let trigger = reactionTrigger, let scene = context.coordinator.scene else { return }
        scene.spawnReaction(at: trigger.point, emoji: trigger.emoji)
        // Сбрасываем триггер чтобы реакция не повторялась
        DispatchQueue.main.async {
            reactionTrigger = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var scene: ReactionScene?
    }
}

// MARK: - Reaction Trigger

struct ReactionTrigger: Equatable {
    let point: CGPoint    // в координатах overlay-вью
    let emoji: String
}

// MARK: - SKView Subclass

final class ReactionSKView: SKView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        allowsTransparency = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        allowsTransparency = true
    }
}

// MARK: - Reaction Scene

final class ReactionScene: SKScene {

    private let physicsGravity: CGVector = CGVector(dx: 0, dy: 6)  // лёгкая гравитация вниз

    override func didMove(to view: SKView) {
        physicsWorld.gravity = CGVector(dx: 0, dy: 1.5)  // мягкое падение
    }

    /// Создаёт эмодзи-реакцию в точке и анимирует полёт вверх.
    func spawnReaction(at point: CGPoint, emoji: String) {
        let label = SKLabelNode(text: emoji)
        label.fontSize = 44
        label.position = point
        label.alpha = 0
        label.setScale(0.3)

        // Физика
        label.physicsBody = SKPhysicsBody(circleOfRadius: 20)
        label.physicsBody?.affectedByGravity = true
        label.physicsBody?.allowsRotation = true

        // Случайный разброс по X
        let randomX = CGFloat.random(in: -40...40)
        // Импульс вверх (отрицательный Y = вверх в SpriteKit)
        label.physicsBody?.velocity = CGVector(dx: randomX, dy: -CGFloat.random(in: 250...400))

        addChild(label)

        // Анимация появления
        label.run(.sequence([
            .group([
                .fadeIn(withDuration: 0.15),
                .scale(to: 1.0, duration: 0.2),
            ]),
            .wait(forDuration: 1.2),
            .group([
                .fadeOut(withDuration: 0.5),
                .scale(to: 1.5, duration: 0.5),
            ]),
            .removeFromParent(),
        ]))
    }

    override func update(_ currentTime: TimeInterval) {
        // Удаляем ноды которые улетели за пределы экрана
        for node in children {
            if node.position.y < -100 || node.position.y > size.height + 200 {
                node.removeFromParent()
            }
        }
    }
}
