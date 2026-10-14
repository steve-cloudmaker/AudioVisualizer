import SpriteKit

/// Balls are RTA bands. The claw picks one; the corner window solos that band's envelope over time.
final class ClawScene: SKScene, VisualizerScene, SpritePumpedScene {
    static let id = "claw"
    static let displayName = "Claw"
    static let renderer: SceneRendererKind = .spriteKit

    private var balls: [SKShapeNode] = []
    private var claw: SKShapeNode?
    private var cable: SKShapeNode?
    private var previewDots: [SKShapeNode] = []
    private var previewLabel: SKLabelNode?
    private var picked = 0
    private var timer: TimeInterval = 0
    private var grabPhase: CGFloat = 0
    private var latest = AudioFeatures.silent
    private var hue: CGFloat = 0.08
    private var built = false
    private var lastSize: CGSize = .zero
    private var soloHistory = [Float](repeating: 0, count: 48)
    private weak var hostView: SKView?
    var framePump: (() -> Void)?

    func setFramePump(_ pump: (() -> Void)?) {
        framePump = pump
    }

    func attach(to target: SceneHostTarget) {
        guard case .spriteKit(let view) = target else { return }
        hostView = view
        backgroundColor = SKColor(red: 0.06, green: 0.04, blue: 0.09, alpha: 1)
        scaleMode = .resizeFill
        if view.scene !== self {
            view.presentScene(self)
        }
        if !built, view.bounds.width > 0 {
            size = view.bounds.size
            rebuild()
        }
    }

    func detach() {
        hostView?.presentScene(nil)
        hostView = nil
        framePump = nil
    }

    func handle(_ event: SceneEvent) {
        if case .tap = event { pickRandom() }
    }

    func update(features: AudioFeatures, dt: TimeInterval, preset: VisualizerPreset) {
        latest = features
        hue = CGFloat(preset.hue)
        timer += dt
        grabPhase = min(1, grabPhase + CGFloat(dt) * 1.8)
        if timer > 2.6 || (features.onsetDetected && timer > 0.9) {
            timer = 0
            pickRandom()
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard size.width > 80, abs(size.width - lastSize.width) > 8 else { return }
        rebuild()
    }

    override func update(_ currentTime: TimeInterval) {
        framePump?()
        let bands = DSPConfig.resample(latest.bands, to: max(balls.count, 1))
        for (i, ball) in balls.enumerated() {
            let v = CGFloat(i < bands.count ? bands[i] : 0)
            let selected = i == picked
            ball.setScale((selected ? 0.7 : 0.55) + v * 0.95)
            ball.alpha = 0.4 + v * 0.6
            ball.glowWidth = selected ? 3 : 0
        }
        if let claw, !balls.isEmpty {
            let target = balls[picked % balls.count].position
            let yOff: CGFloat = 40 - CGFloat(grabPhase) * 18
            claw.position.x += (target.x - claw.position.x) * 0.1
            claw.position.y += ((target.y + yOff) - claw.position.y) * 0.1
            if let cable {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: claw.position.x, y: size.height))
                path.addLine(to: claw.position)
                cable.path = path
            }
        }
        if picked < bands.count {
            soloHistory.removeFirst()
            soloHistory.append(bands[picked])
        }
        for (i, dot) in previewDots.enumerated() {
            let v = CGFloat(i < soloHistory.count ? soloHistory[i] : 0)
            dot.yScale = 0.15 + v * 1.7
            dot.alpha = 0.35 + v * 0.65
        }
        previewLabel?.text = "SOLO  BAND \(picked + 1)"
    }

    private func rebuild() {
        removeAllChildren()
        balls.removeAll()
        previewDots.removeAll()
        lastSize = size
        physicsWorld.gravity = .zero

        let title = SKLabelNode(text: "CLAW  ·  balls = bands  ·  window = solo")
        title.fontName = "Menlo-Bold"
        title.fontSize = 12
        title.fontColor = SKColor(white: 0.88, alpha: 0.85)
        title.position = CGPoint(x: size.width / 2, y: size.height - 26)
        addChild(title)

        let cols = 8
        let rows = 4
        let count = cols * rows
        let margin: CGFloat = 40
        let previewWidth: CGFloat = 150
        for i in 0..<count {
            let col = i % cols
            let row = i / cols
            let x = margin + (size.width - margin * 2 - previewWidth) * (CGFloat(col) + 0.5) / CGFloat(cols)
            let y = 90 + (size.height - 150) * (CGFloat(row) + 0.5) / CGFloat(rows)
            let ball = SKShapeNode(circleOfRadius: 18)
            ball.position = CGPoint(x: x, y: y)
            ball.fillColor = SKColor(hue: CGFloat(i) / CGFloat(count), saturation: 0.5, brightness: 0.96, alpha: 1)
            ball.strokeColor = SKColor(white: 1, alpha: 0.25)
            addChild(ball)
            balls.append(ball)
        }

        let cableNode = SKShapeNode()
        cableNode.strokeColor = SKColor(white: 0.75, alpha: 0.9)
        cableNode.lineWidth = 2
        addChild(cableNode)
        cable = cableNode

        let clawNode = SKShapeNode(rectOf: CGSize(width: 34, height: 16), cornerRadius: 3)
        clawNode.fillColor = SKColor(white: 0.9, alpha: 1)
        clawNode.strokeColor = .clear
        clawNode.position = CGPoint(x: size.width / 2, y: size.height - 50)
        let left = SKShapeNode(rectOf: CGSize(width: 6, height: 18), cornerRadius: 1)
        left.position = CGPoint(x: -14, y: -14)
        left.fillColor = SKColor(white: 0.9, alpha: 1)
        left.strokeColor = .clear
        clawNode.addChild(left)
        let right = SKShapeNode(rectOf: CGSize(width: 6, height: 18), cornerRadius: 1)
        right.position = CGPoint(x: 14, y: -14)
        right.fillColor = SKColor(white: 0.9, alpha: 1)
        right.strokeColor = .clear
        clawNode.addChild(right)
        addChild(clawNode)
        claw = clawNode

        let window = SKShapeNode(rectOf: CGSize(width: 132, height: 108), cornerRadius: 4)
        window.position = CGPoint(x: size.width - 84, y: 78)
        window.strokeColor = SKColor(white: 0.92, alpha: 0.7)
        window.fillColor = SKColor(white: 0, alpha: 0.4)
        window.lineWidth = 1.5
        addChild(window)

        let label = SKLabelNode(text: "SOLO")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = SKColor(white: 0.9, alpha: 0.85)
        label.position = CGPoint(x: size.width - 84, y: 118)
        addChild(label)
        previewLabel = label

        let barCount = 24
        for i in 0..<barCount {
            let bar = SKShapeNode(rectOf: CGSize(width: 3.5, height: 36), cornerRadius: 0.5)
            bar.position = CGPoint(x: size.width - 140 + CGFloat(i) * 4.6, y: 64)
            bar.fillColor = SKColor(hue: hue, saturation: 0.85, brightness: 1, alpha: 1)
            bar.strokeColor = .clear
            addChild(bar)
            previewDots.append(bar)
        }
        built = true
    }

    private func pickRandom() {
        guard !balls.isEmpty else { return }
        picked = Int.random(in: 0..<balls.count)
        grabPhase = 0
        soloHistory = [Float](repeating: 0, count: soloHistory.count)
    }
}
