import SwiftUI

/// Modular DAW strip: waterfall, waveform, chromagram, loudness, spectrum, goniometer.
final class AnalyzerStripScene: CanvasDrawableScene {
    static let id = "analyzer-strip"
    static let displayName = "Analyzer Strip"
    static let renderer: SceneRendererKind = .canvas

    private var history: [[Float]] = []
    private let historyDepth = 96
    private var lastPresetHue: Float = 0.05

    func attach(to target: SceneHostTarget) {}
    func detach() {}
    func handle(_ event: SceneEvent) {
        if case .randomize = event {
            history.removeAll()
        }
    }

    func update(features: AudioFeatures, dt: TimeInterval, preset: VisualizerPreset) {
        history.append(features.bands)
        if history.count > historyDepth {
            history.removeFirst(history.count - historyDepth)
        }
        lastPresetHue = preset.hue
    }

    func draw(_ context: GraphicsContext, size: CGSize, features: AudioFeatures, preset: VisualizerPreset) {
        let accent = Color(hue: Double(preset.hue), saturation: Double(preset.saturation), brightness: 0.95)
        let dim = Color(hue: Double(preset.hue), saturation: Double(preset.saturation) * 0.5, brightness: 0.25)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.03, green: 0.02, blue: 0.02)))

        let gap: CGFloat = 6
        let columns = 6
        let width = (size.width - gap * CGFloat(columns + 1)) / CGFloat(columns)
        let y = 28.0
        let height = size.height - 44
        let labels = ["WATERFALL", "WAVE", "CHROMA", "LOUDNESS", "RESPONSE", "GONIO"]

        for i in 0..<columns {
            let rect = CGRect(x: gap + CGFloat(i) * (width + gap), y: y, width: width, height: height)
            var frame = Path()
            frame.addRect(rect)
            context.stroke(frame, with: .color(accent.opacity(0.35)), lineWidth: 1)

            var label = context
            label.opacity = 0.7
            label.draw(
                Text(labels[i]).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(accent),
                at: CGPoint(x: rect.minX + 8, y: 14)
            )

            let inner = rect.insetBy(dx: 6, dy: 8)
            switch i {
            case 0: drawWaterfall(context, in: inner, accent: accent)
            case 1: drawWave(context, in: inner, features: features, accent: accent)
            case 2: drawChroma(context, in: inner, features: features, accent: accent)
            case 3: drawLoudness(context, in: inner, features: features, accent: accent, dim: dim)
            case 4: drawSpectrum(context, in: inner, features: features, accent: accent)
            default: drawGoniometer(context, in: inner, features: features, accent: accent)
            }
        }
    }

    private func drawWaterfall(_ context: GraphicsContext, in rect: CGRect, accent: Color) {
        guard !history.isEmpty else { return }
        let rows = history.count
        let rowH = rect.height / CGFloat(rows)
        for (row, bands) in history.enumerated() {
            guard !bands.isEmpty else { continue }
            let colW = rect.width / CGFloat(bands.count)
            for (col, value) in bands.enumerated() {
                let v = CGFloat(max(0, min(1, value)))
                let cell = CGRect(
                    x: rect.minX + CGFloat(col) * colW,
                    y: rect.minY + CGFloat(row) * rowH,
                    width: max(1, colW),
                    height: max(1, rowH)
                )
                let color = Color(
                    hue: Double(lastPresetHue) + Double(col) * 0.001,
                    saturation: 0.9,
                    brightness: 0.15 + 0.85 * v
                )
                context.fill(Path(cell), with: .color(color.opacity(0.35 + 0.65 * v)))
            }
        }
        _ = accent
    }

    private func drawWave(_ context: GraphicsContext, in rect: CGRect, features: AudioFeatures, accent: Color) {
        let samples = features.waveform
        guard samples.count > 1 else { return }
        var path = Path()
        let midY = rect.midY
        let amp = rect.height * 0.42
        for (i, sample) in samples.enumerated() {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(samples.count - 1)
            let y = midY - CGFloat(sample) * amp
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(accent), lineWidth: 1.2)

        var lPath = Path()
        for (i, sample) in features.waveformL.enumerated() {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(max(features.waveformL.count - 1, 1))
            let y = midY - CGFloat(sample) * amp * 0.6
            if i == 0 { lPath.move(to: CGPoint(x: x, y: y)) }
            else { lPath.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(lPath, with: .color(accent.opacity(0.35)), lineWidth: 0.8)
    }

    private func drawChroma(_ context: GraphicsContext, in rect: CGRect, features: AudioFeatures, accent: Color) {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let chroma = features.chroma
        let n = max(chroma.count, 1)
        let w = rect.width / CGFloat(n)
        for i in 0..<n {
            let v = CGFloat(i < chroma.count ? chroma[i] : 0)
            let barH = rect.height * 0.75 * v
            let x = rect.minX + CGFloat(i) * w
            let bar = CGRect(x: x + 2, y: rect.maxY - 16 - barH, width: max(2, w - 4), height: barH)
            let lit = i == features.pitchClass && features.pitchConfidence > 0.2
            context.fill(Path(bar), with: .color(accent.opacity(lit ? 1 : 0.35 + 0.65 * v)))
            context.draw(
                Text(names[i % 12]).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(accent.opacity(0.8)),
                at: CGPoint(x: x + w / 2, y: rect.maxY - 8)
            )
        }
    }

    private func drawLoudness(_ context: GraphicsContext, in rect: CGRect, features: AudioFeatures, accent: Color, dim: Color) {
        let db = features.loudnessDB
        let label = String(format: "%5.1f dB", db)
        context.draw(
            Text(label).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundColor(accent),
            at: CGPoint(x: rect.midX, y: rect.minY + 24)
        )
        let bpm = features.bpm > 0 ? String(format: "%.0f BPM", features.bpm) : (features.isSilent ? "GATE" : "MOMENTARY")
        context.draw(
            Text(bpm).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(accent.opacity(0.6)),
            at: CGPoint(x: rect.midX, y: rect.minY + 46)
        )

        let meter = CGRect(x: rect.midX - 18, y: rect.minY + 60, width: 36, height: rect.height - 80)
        context.stroke(Path(meter), with: .color(accent.opacity(0.4)), lineWidth: 1)
        let fillFrac = CGFloat(max(0, min(1, (db + 60) / 60)))
        let fillH = meter.height * fillFrac
        let fill = CGRect(x: meter.minX + 2, y: meter.maxY - fillH, width: meter.width - 4, height: fillH)
        context.fill(Path(fill), with: .color(accent.opacity(0.85)))

        let rmsW = rect.width * 0.7 * CGFloat(features.rms)
        context.fill(
            Path(CGRect(x: rect.midX - rmsW / 2, y: rect.maxY - 12, width: rmsW, height: 4)),
            with: .color(dim)
        )
    }

    private func drawSpectrum(_ context: GraphicsContext, in rect: CGRect, features: AudioFeatures, accent: Color) {
        let bands = features.bands
        let peaks = features.bandsPeak
        guard !bands.isEmpty else { return }
        let w = rect.width / CGFloat(bands.count)
        var curve = Path()
        for (i, value) in bands.enumerated() {
            let x = rect.minX + CGFloat(i) * w + w / 2
            let y = rect.maxY - CGFloat(value) * rect.height * 0.92
            if i == 0 { curve.move(to: CGPoint(x: x, y: y)) }
            else { curve.addLine(to: CGPoint(x: x, y: y)) }
            let peakY = rect.maxY - CGFloat(i < peaks.count ? peaks[i] : 0) * rect.height * 0.92
            let hold = CGRect(x: x - max(1, w / 2), y: peakY, width: max(1, w - 1), height: 2)
            context.fill(Path(hold), with: .color(accent.opacity(0.9)))
        }
        context.stroke(curve, with: .color(accent), lineWidth: 1.4)
    }

    private func drawGoniometer(_ context: GraphicsContext, in rect: CGRect, features: AudioFeatures, accent: Color) {
        let side = min(rect.width, rect.height) - 8
        let square = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        context.stroke(Path(ellipseIn: square), with: .color(accent.opacity(0.35)), lineWidth: 1)
        var axes = Path()
        axes.move(to: CGPoint(x: square.midX, y: square.minY))
        axes.addLine(to: CGPoint(x: square.midX, y: square.maxY))
        axes.move(to: CGPoint(x: square.minX, y: square.midY))
        axes.addLine(to: CGPoint(x: square.maxX, y: square.midY))
        context.stroke(axes, with: .color(accent.opacity(0.2)), lineWidth: 1)

        for (i, point) in features.goniometer.enumerated() {
            let x = square.midX + CGFloat(point.x) * side * 0.45
            let y = square.midY - CGFloat(point.y) * side * 0.45
            let alpha = 0.15 + 0.85 * Double(i) / Double(max(features.goniometer.count, 1))
            let dot = CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)
            context.fill(Path(ellipseIn: dot), with: .color(accent.opacity(alpha)))
        }

        let corr = String(format: "r %+0.2f  w %.2f", features.correlation, features.stereoWidth)
        context.draw(
            Text(corr).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(accent.opacity(0.8)),
            at: CGPoint(x: rect.midX, y: rect.maxY - 8)
        )
    }
}
