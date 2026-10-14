import SwiftUI

/// Original vector micrographics driven by the skin format. Optional SVGs load from Application Support.
final class MicrographicScene: CanvasDrawableScene {
    static let id = "micrographic"
    static let displayName = "Micrographic"
    static let renderer: SceneRendererKind = .canvas

    var skin: MicrographicSkin = .placeholder
    private var latest = AudioFeatures.silent
    private var time: TimeInterval = 0

    func attach(to target: SceneHostTarget) {
        if let loaded = SVGSkinLoader.applicationSupportSkins().first {
            skin = loaded
        }
    }

    func detach() {}

    func handle(_ event: SceneEvent) {
        if case .randomize = event, let next = SVGSkinLoader.applicationSupportSkins().randomElement() {
            skin = next
        }
    }

    func update(features: AudioFeatures, dt: TimeInterval, preset: VisualizerPreset) {
        latest = features
        time += dt
        _ = preset
    }

    func draw(_ context: GraphicsContext, size: CGSize, features: AudioFeatures, preset: VisualizerPreset) {
        let accent = Color(hue: Double(preset.hue), saturation: Double(preset.saturation), brightness: 0.95)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.05, green: 0.04, blue: 0.035)))

        context.draw(
            Text(skin.name.uppercased())
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(accent),
            at: CGPoint(x: size.width / 2, y: 24)
        )

        let values = Dictionary(uniqueKeysWithValues: skin.layers.map { ($0.id, skin.value(for: $0, features: features)) })
        func v(_ id: String, fallback: Float = 0) -> CGFloat {
            CGFloat(values[id] ?? fallback)
        }

        drawSun(context, origin: CGPoint(x: size.width * 0.18, y: size.height * 0.32), energy: v("sun", fallback: features.rms), accent: accent)
        drawFlame(context, origin: CGPoint(x: size.width * 0.38, y: size.height * 0.62), energy: v("flame", fallback: features.bass), accent: accent)
        drawArch(context, origin: CGPoint(x: size.width * 0.62, y: size.height * 0.48), energy: v("band-low", fallback: features.mid), accent: accent)
        drawCloud(context, origin: CGPoint(x: size.width * 0.8, y: size.height * 0.28), energy: v("cloud", fallback: features.treble), accent: accent)
        drawSpark(context, origin: CGPoint(x: size.width * 0.5, y: size.height * 0.28), energy: v("spark", fallback: features.onset), accent: accent)
        drawKey(context, origin: CGPoint(x: size.width * 0.22, y: size.height * 0.78), energy: v("key-a", fallback: features.chroma.indices.contains(9) ? features.chroma[9] : 0), accent: accent)
        drawPlanet(context, origin: CGPoint(x: size.width * 0.78, y: size.height * 0.72), energy: v("band-high", fallback: features.treble), accent: accent, time: time)

        let caption = skin.svgResource == "micrographic-placeholder"
            ? "built-in motifs  ·  drop SVGs in Application Support/AudioVisualizer/Skins"
            : "loaded  \(skin.svgResource)"
        context.draw(
            Text(caption)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(accent.opacity(0.65)),
            at: CGPoint(x: size.width / 2, y: size.height - 18)
        )
    }

    private func drawSun(_ context: GraphicsContext, origin: CGPoint, energy: CGFloat, accent: Color) {
        let r = 28 + energy * 22
        var disc = Path(ellipseIn: CGRect(x: origin.x - r, y: origin.y - r, width: r * 2, height: r * 2))
        context.fill(disc, with: .color(accent.opacity(0.85)))
        for i in 0..<12 {
            let a = Double(i) / 12 * .pi * 2
            var ray = Path()
            ray.move(to: CGPoint(x: origin.x + cos(a) * r * 1.15, y: origin.y + sin(a) * r * 1.15))
            ray.addLine(to: CGPoint(x: origin.x + cos(a) * r * (1.45 + energy * 0.4), y: origin.y + sin(a) * r * (1.45 + energy * 0.4)))
            context.stroke(ray, with: .color(accent.opacity(0.7)), lineWidth: 2)
        }
        _ = disc
    }

    private func drawFlame(_ context: GraphicsContext, origin: CGPoint, energy: CGFloat, accent: Color) {
        var path = Path()
        let h = 40 + energy * 50
        path.move(to: CGPoint(x: origin.x, y: origin.y - h))
        path.addCurve(
            to: CGPoint(x: origin.x + 22, y: origin.y + 20),
            control1: CGPoint(x: origin.x + 18, y: origin.y - h * 0.4),
            control2: CGPoint(x: origin.x + 28, y: origin.y - 4)
        )
        path.addQuadCurve(to: CGPoint(x: origin.x - 22, y: origin.y + 20), control: CGPoint(x: origin.x, y: origin.y + 36))
        path.addCurve(
            to: CGPoint(x: origin.x, y: origin.y - h),
            control1: CGPoint(x: origin.x - 28, y: origin.y - 4),
            control2: CGPoint(x: origin.x - 18, y: origin.y - h * 0.4)
        )
        context.fill(path, with: .color(accent.opacity(0.55 + 0.4 * energy)))
    }

    private func drawArch(_ context: GraphicsContext, origin: CGPoint, energy: CGFloat, accent: Color) {
        var arch = Path()
        let w: CGFloat = 54
        let h: CGFloat = 70
        arch.move(to: CGPoint(x: origin.x - w, y: origin.y + h / 2))
        arch.addLine(to: CGPoint(x: origin.x - w, y: origin.y))
        arch.addQuadCurve(to: CGPoint(x: origin.x + w, y: origin.y), control: CGPoint(x: origin.x, y: origin.y - h * (0.7 + energy * 0.25)))
        arch.addLine(to: CGPoint(x: origin.x + w, y: origin.y + h / 2))
        context.stroke(arch, with: .color(accent.opacity(0.8)), lineWidth: 3)
        let flame = Path(ellipseIn: CGRect(x: origin.x - 6, y: origin.y - 8 - energy * 16, width: 12, height: 14 + energy * 18))
        context.fill(flame, with: .color(accent.opacity(0.9)))
    }

    private func drawCloud(_ context: GraphicsContext, origin: CGPoint, energy: CGFloat, accent: Color) {
        let a = 0.25 + 0.7 * energy
        for offset in [-22.0, 0.0, 24.0] {
            let r = 16 + energy * 8
            context.fill(
                Path(ellipseIn: CGRect(x: origin.x + offset - r, y: origin.y - r * 0.6, width: r * 2, height: r * 1.3)),
                with: .color(accent.opacity(Double(a) * 0.55))
            )
        }
    }

    private func drawSpark(_ context: GraphicsContext, origin: CGPoint, energy: CGFloat, accent: Color) {
        guard energy > 0.05 else { return }
        var star = Path()
        for i in 0..<8 {
            let a = Double(i) / 8 * .pi * 2 - .pi / 2
            let r = (i.isMultiple(of: 2) ? 8 : 20) * (0.4 + energy)
            let p = CGPoint(x: origin.x + cos(a) * r, y: origin.y + sin(a) * r)
            if i == 0 { star.move(to: p) } else { star.addLine(to: p) }
        }
        star.closeSubpath()
        context.fill(star, with: .color(accent.opacity(Double(energy))))
    }

    private func drawKey(_ context: GraphicsContext, origin: CGPoint, energy: CGFloat, accent: Color) {
        let rect = CGRect(x: origin.x - 16, y: origin.y - 28, width: 32, height: 56)
        context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(accent.opacity(0.2 + 0.75 * energy)))
        context.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(accent), lineWidth: 1)
        context.draw(
            Text("A")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(energy > 0.35 ? .black : accent),
            at: origin
        )
    }

    private func drawPlanet(_ context: GraphicsContext, origin: CGPoint, energy: CGFloat, accent: Color, time: TimeInterval) {
        let r = 22 + energy * 10
        context.stroke(Path(ellipseIn: CGRect(x: origin.x - r, y: origin.y - r, width: r * 2, height: r * 2)), with: .color(accent), lineWidth: 2)
        var ring = Path()
        ring.addEllipse(in: CGRect(x: origin.x - r * 1.6, y: origin.y - 6, width: r * 3.2, height: 12))
        context.stroke(ring, with: .color(accent.opacity(0.6)), lineWidth: 1.5)
        let satA = time * (0.8 + Double(energy))
        let sat = CGPoint(x: origin.x + cos(satA) * r * 1.55, y: origin.y + sin(satA) * 7)
        context.fill(Path(ellipseIn: CGRect(x: sat.x - 4, y: sat.y - 4, width: 8, height: 8)), with: .color(accent))
    }
}
