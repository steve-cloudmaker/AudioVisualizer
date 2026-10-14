import SpriteKit

/// Buckets are a log RTA. Balls drop on onsets (and a slow idle drip) so silence isn't a freeze-frame.
final class PlinkoScene: SKScene, VisualizerScene, SpritePumpedScene {
    static let id = "plinko"
    static let displayName = "Plinko"
    static let renderer: SceneRendererKind = .spriteKit

    private var buckets: [SKShapeNode] = []
    private var bucketFills: [SKShapeNode] = []
    private var built = false
    private var idle: TimeInterval = 0
    private var lastOnset = false
    private var latest = AudioFeatures.silent
    private var hue: CGFloat = 0.05
    private var lastSize: CGSize = .zero
    private weak var hostView: SKView?
    var framePump: (() -> Void)?

    func setFramePump(_ pump: (() -> Void)?) {
        framePump = pump
    }

    func attach(to target: SceneHostTarget) {
        guard case .spriteKit(let view) = target else { return }
        hostView = view
        backgroundColor = SKColor(red: 0.04, green: 0.03, blue: 0.07, alpha: 1)
        scaleMode = .resizeFill
        if view.scene !== self {
            view.presentScene(self)
        }
        if !built, view.bounds.width > 0 {
            size = view.bounds.size
            rebuildBoard()
        }
    }

    func detach() {
        hostView?.presentScene(nil)
        hostView = nil
        framePump = nil
    }

    func handle(_ event: SceneEvent) {
        if case .tap = event { dropBall(boosted: true) }
        if case .randomize = event { dropBall(boosted: true) }
    }

    func update(features: AudioFeatures, dt: TimeInterval, preset: VisualizerPreset) {
        latest = features
        hue = CGFloat(preset.hue)
        if features.onsetDetected && !lastOnset {
            dropBall(boosted: features.bass > 0.55)
        }
        lastOnset = features.onsetDetected
        idle += dt
        let drip = features.isSilent ? 2.4 : 1.6
        if idle > drip {
            idle = 0
            dropBall(boosted: false)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard size.width > 80, abs(size.width - lastSize.width) > 8 || abs(size.height - lastSize.height) > 8 else { return }
        rebuildBoard()
    }

    override func update(_ currentTime: TimeInterval) {
        framePump?()
        let n = buckets.count
        guard n > 0 else { return }
        let bands = DSPConfig.resample(latest.bands, to: n)
        for (i, fill) in bucketFills.enumerated() {
            let v = CGFloat(bands[i])
            fill.yScale = max(0.08, v)
            fill.alpha = 0.35 + v * 0.65
        }
        enumerateChildNodes(withName: "ball") { node, _ in
            if node.position.y < -40 {
                node.removeFromParent()
            }
        }
    }

    private func rebuildBoard() {
        removeAllChildren()
        buckets.removeAll()
        bucketFills.removeAll()
        lastSize = size
        physicsWorld.gravity = CGVector(dx: 0, dy: -7.2)
        physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(origin: .zero, size: size))

        let title = SKLabelNode(text: "PLINKO  ·  buckets = spectrum  ·  balls = beats")
        title.fontName = "Menlo-Bold"
        title.fontSize = 12
        title.fontColor = SKColor(white: 0.85, alpha: 0.85)
        title.position = CGPoint(x: size.width / 2, y: size.height - 26)
        addChild(title)

        let rows = 8
        let pegR: CGFloat = max(3.5, size.width * 0.0045)
        for row in 0..<rows {
            let count = row + 5
            for col in 0..<count {
                let x = size.width * (CGFloat(col) + 1) / CGFloat(count + 1)
                let y = size.height * 0.82 - CGFloat(row) * (size.height * 0.068)
                let peg = SKShapeNode(circleOfRadius: pegR)
                peg.position = CGPoint(x: x, y: y)
                peg.fillColor = SKColor(white: 0.82, alpha: 1)
                peg.strokeColor = SKColor(white: 1, alpha: 0.15)
                peg.glowWidth = 0.5
                peg.physicsBody = SKPhysicsBody(circleOfRadius: pegR)
                peg.physicsBody?.isDynamic = false
                peg.physicsBody?.restitution = 0.45
                addChild(peg)
            }
        }

        let bucketCount = 16
        let bw = size.width / CGFloat(bucketCount)
        let floorY: CGFloat = 36
        for i in 0..<bucketCount {
            let x = bw * (CGFloat(i) + 0.5)
            let wall = SKNode()
            wall.position = CGPoint(x: CGFloat(i) * bw, y: floorY)
            wall.physicsBody = SKPhysicsBody(edgeFrom: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 52))
            addChild(wall)

            let well = SKShapeNode(rectOf: CGSize(width: bw - 3, height: 48), cornerRadius: 2)
            well.position = CGPoint(x: x, y: floorY)
            well.strokeColor = SKColor(hue: hue + CGFloat(i) / 48, saturation: 0.55, brightness: 1, alpha: 0.9)
            well.fillColor = SKColor(white: 0.05, alpha: 0.6)
            well.lineWidth = 1.2
            addChild(well)
            buckets.append(well)

            let fill = SKShapeNode(rectOf: CGSize(width: bw - 8, height: 40), cornerRadius: 1)
            fill.position = CGPoint(x: x, y: floorY)
            fill.fillColor = SKColor(hue: hue + CGFloat(i) / 48, saturation: 0.85, brightness: 1, alpha: 1)
            fill.strokeColor = .clear
            fill.yScale = 0.1
            addChild(fill)
            bucketFills.append(fill)
        }

        let rightWall = SKNode()
        rightWall.position = CGPoint(x: size.width, y: floorY)
        rightWall.physicsBody = SKPhysicsBody(edgeFrom: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 52))
        addChild(rightWall)

        built = true
    }

    private func dropBall(boosted: Bool) {
        guard size.width > 0 else { return }
        let radius: CGFloat = boosted ? 7.5 : 6
        let ball = SKShapeNode(circleOfRadius: radius)
        ball.position = CGPoint(
            x: size.width * 0.5 + CGFloat.random(in: -size.width * 0.08...size.width * 0.08),
            y: size.height - 48
        )
        let energy = CGFloat(max(latest.bass, latest.mid))
        ball.fillColor = SKColor(hue: hue + energy * 0.08, saturation: 0.85, brightness: 1, alpha: 1)
        ball.strokeColor = .clear
        ball.glowWidth = boosted ? 2 : 0.5
        ball.physicsBody = SKPhysicsBody(circleOfRadius: radius)
        ball.physicsBody?.restitution = 0.38
        ball.physicsBody?.linearDamping = 0.04
        ball.physicsBody?.angularDamping = 0.4
        ball.name = "ball"
        addChild(ball)

        let existing = children.filter { $0.name == "ball" }
        if existing.count > 48 {
            existing.first?.removeFromParent()
        }
    }
}
