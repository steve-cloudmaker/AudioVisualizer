import Foundation

/// Loads a minimal SVG as a `MicrographicSkin` by mapping element `id`s to feature-bus modulators.
/// Drop files in Application Support/AudioVisualizer/Skins/*.svg — we do not bundle paid packs.
enum SVGSkinLoader {
    static func applicationSupportSkins() -> [MicrographicSkin] {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AudioVisualizer/Skins", isDirectory: true)
        guard let folder else { return [] }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? []
        return files.filter { $0.pathExtension.lowercased() == "svg" }.compactMap { load(from: $0) }
    }

    static func load(from url: URL) -> MicrographicSkin? {
        guard let xml = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(xml: xml, name: url.deletingPathExtension().lastPathComponent, resource: url.lastPathComponent)
    }

    static func parse(xml: String, name: String, resource: String) -> MicrographicSkin {
        let ids = captureIDs(in: xml)
        let layers = ids.map { id -> MicrographicSkin.Layer in
            let modulator = modulator(for: id)
            return MicrographicSkin.Layer(
                id: id,
                modulator: modulator.mod,
                bandIndex: modulator.band,
                chromaIndex: modulator.chroma,
                property: property(for: id),
                amount: 1
            )
        }
        return MicrographicSkin(name: name, svgResource: resource, layers: layers)
    }

    static func modulator(for id: String) -> (mod: MicrographicSkin.Modulator, band: Int?, chroma: Int?) {
        let key = id.lowercased()
        if key.contains("bass") || key.contains("flame") || key.contains("fire") { return (.bass, nil, nil) }
        if key.contains("mid") { return (.mid, nil, nil) }
        if key.contains("treble") || key.contains("spark") || key.contains("star") { return (.treble, nil, nil) }
        if key.contains("onset") || key.contains("beat") || key.contains("kick") { return (.onset, nil, nil) }
        if key.contains("rms") || key.contains("sun") || key.contains("level") { return (.rms, nil, nil) }
        if let match = key.range(of: #"band[-_]?(\d{1,3})"#, options: .regularExpression) {
            let digits = key[match].filter(\.isNumber)
            return (.band, Int(digits), nil)
        }
        let notes = ["c", "c#", "d", "d#", "e", "f", "f#", "g", "g#", "a", "a#", "b"]
        for (i, note) in notes.enumerated() where key == "key-\(note)" || key == "chroma-\(note)" {
            return (.chroma, nil, i)
        }
        return (.rms, nil, nil)
    }

    static func property(for id: String) -> MicrographicSkin.AnimatableProperty {
        let key = id.lowercased()
        if key.contains("spark") || key.contains("cloud") || key.contains("star") { return .opacity }
        if key.contains("rotate") || key.contains("wheel") { return .rotation }
        if key.contains("fill") || key.contains("glow") { return .fillBrightness }
        return .scale
    }

    private static func captureIDs(in xml: String) -> [String] {
        let pattern = #"id=["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        return regex.matches(in: xml, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: xml) else { return nil }
            return String(xml[r])
        }
    }
}
