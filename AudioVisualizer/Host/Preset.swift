import Foundation

struct VisualizerPreset: Codable, Equatable {
    var sceneID: String
    var name: String
    var sensitivity: Float
    var bandCount: Int
    var hue: Float
    var saturation: Float
    var shuffleOnBeat: Bool
    var hapticsEnabled: Bool

    static let `default` = VisualizerPreset(
        sceneID: AnalyzerStripScene.id,
        name: "Init",
        sensitivity: 1,
        bandCount: DSPConfig.defaultBandCount,
        hue: 0.05,
        saturation: 0.85,
        shuffleOnBeat: false,
        hapticsEnabled: false
    )

    static let factory: [VisualizerPreset] = [
        .default,
        VisualizerPreset(
            sceneID: HallOfTorchesScene.id,
            name: "Hall Orange",
            sensitivity: 1.15,
            bandCount: 64,
            hue: 0.045,
            saturation: 0.95,
            shuffleOnBeat: false,
            hapticsEnabled: false
        ),
        VisualizerPreset(
            sceneID: AnalyzerStripScene.id,
            name: "Cool Strip",
            sensitivity: 0.9,
            bandCount: 128,
            hue: 0.55,
            saturation: 0.7,
            shuffleOnBeat: false,
            hapticsEnabled: false
        ),
        VisualizerPreset(
            sceneID: AnalyzerStripScene.id,
            name: "Shuffle",
            sensitivity: 1.0,
            bandCount: 64,
            hue: 0.08,
            saturation: 0.8,
            shuffleOnBeat: true,
            hapticsEnabled: false
        )
    ]

    static func mix(_ a: VisualizerPreset, _ b: VisualizerPreset, t: Float) -> VisualizerPreset {
        let u = max(0, min(1, t))
        return VisualizerPreset(
            sceneID: u < 0.5 ? a.sceneID : b.sceneID,
            name: u < 0.5 ? a.name : b.name,
            sensitivity: lerp(a.sensitivity, b.sensitivity, u),
            bandCount: u < 0.5 ? a.bandCount : b.bandCount,
            hue: lerpHue(a.hue, b.hue, u),
            saturation: lerp(a.saturation, b.saturation, u),
            shuffleOnBeat: u < 0.5 ? a.shuffleOnBeat : b.shuffleOnBeat,
            hapticsEnabled: u < 0.5 ? a.hapticsEnabled : b.hapticsEnabled
        )
    }

    private static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }

    private static func lerpHue(_ a: Float, _ b: Float, _ t: Float) -> Float {
        var delta = b - a
        if delta > 0.5 { delta -= 1 }
        if delta < -0.5 { delta += 1 }
        var h = a + delta * t
        if h < 0 { h += 1 }
        if h > 1 { h -= 1 }
        return h
    }
}

@MainActor
final class PresetStore: ObservableObject {
    @Published private(set) var presets: [VisualizerPreset]
    @Published var selectedName: String

    init() {
        let loaded = Self.loadFromDisk()
        let initial = (loaded?.isEmpty == false) ? loaded! : VisualizerPreset.factory
        presets = initial
        selectedName = initial.first?.name ?? VisualizerPreset.default.name
    }

    func preset(named name: String) -> VisualizerPreset? {
        presets.first { $0.name == name }
    }

    func save(_ preset: VisualizerPreset) {
        if let idx = presets.firstIndex(where: { $0.name == preset.name }) {
            presets[idx] = preset
        } else {
            presets.append(preset)
        }
        selectedName = preset.name
        persist()
    }

    private func persist() {
        guard let url = Self.fileURL() else { return }
        do {
            let data = try JSONEncoder().encode(presets)
            try data.write(to: url, options: .atomic)
        } catch {
            // Local cache; failure is non-fatal.
        }
    }

    private static func loadFromDisk() -> [VisualizerPreset]? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([VisualizerPreset].self, from: data)
    }

    private static func fileURL() -> URL? {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AudioVisualizer", isDirectory: true)
        guard let folder else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("presets.json")
    }
}
