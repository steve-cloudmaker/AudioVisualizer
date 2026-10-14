import Foundation

/// Skin format for licensed SVG micrographic packs (e.g. Fox Rockett Micrographics Vol.1).
/// Map layer IDs in the SVG to modulators on the feature bus. Do not bundle assets without a license.
struct MicrographicSkin: Codable, Equatable {
    var name: String
    var svgResource: String
    var layers: [Layer]

    struct Layer: Codable, Equatable {
        var id: String
        var modulator: Modulator
        var bandIndex: Int?
        var chromaIndex: Int?
        var property: AnimatableProperty
        var amount: Float
    }

    enum Modulator: String, Codable {
        case bass
        case mid
        case treble
        case rms
        case onset
        case band
        case chroma
    }

    enum AnimatableProperty: String, Codable {
        case scale
        case opacity
        case rotation
        case fillBrightness
    }

    func value(for layer: Layer, features: AudioFeatures) -> Float {
        let raw: Float
        switch layer.modulator {
        case .bass: raw = features.bass
        case .mid: raw = features.mid
        case .treble: raw = features.treble
        case .rms: raw = features.rms
        case .onset: raw = features.onset
        case .band:
            let idx = min(max(layer.bandIndex ?? 0, 0), max(features.bands.count - 1, 0))
            raw = features.bands.isEmpty ? 0 : features.bands[idx]
        case .chroma:
            let idx = min(max(layer.chromaIndex ?? 0, 0), 11)
            raw = idx < features.chroma.count ? features.chroma[idx] : 0
        }
        return raw * layer.amount
    }

    static let placeholder = MicrographicSkin(
        name: "Placeholder Atlas",
        svgResource: "micrographic-placeholder",
        layers: [
            Layer(id: "sun", modulator: .rms, bandIndex: nil, chromaIndex: nil, property: .scale, amount: 0.6),
            Layer(id: "flame", modulator: .bass, bandIndex: nil, chromaIndex: nil, property: .scale, amount: 1),
            Layer(id: "spark", modulator: .onset, bandIndex: nil, chromaIndex: nil, property: .opacity, amount: 1),
            Layer(id: "cloud", modulator: .treble, bandIndex: nil, chromaIndex: nil, property: .opacity, amount: 0.8),
            Layer(id: "band-low", modulator: .band, bandIndex: 4, chromaIndex: nil, property: .fillBrightness, amount: 1),
            Layer(id: "band-high", modulator: .band, bandIndex: 48, chromaIndex: nil, property: .fillBrightness, amount: 1),
            Layer(id: "key-a", modulator: .chroma, bandIndex: nil, chromaIndex: 9, property: .scale, amount: 0.7)
        ]
    )
}
