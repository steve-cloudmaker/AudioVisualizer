import Foundation

/// Immutable snapshot published by the analysis thread and consumed by scenes.
/// Arrays are small (bands ≤ 128, waveform 256, chroma 12) so copying at 60–120 Hz is cheap.
struct AudioFeatures: Sendable {
    var sampleRate: Float
    var timestamp: TimeInterval

    /// Downsampled mono waveform in `-1...1`, length `DSPConfig.waveformPoints`.
    var waveform: [Float]
    var waveformL: [Float]
    var waveformR: [Float]

    /// Linear-frequency FFT magnitudes (FFT/2 bins), not AGC-normalized.
    var fftMagnitudes: [Float]

    /// Log-spaced RTA bands after envelope + AGC, `0...1`.
    var bands: [Float]
    /// Peak-hold per band, `0...1`.
    var bandsPeak: [Float]

    var rms: Float
    var peak: Float
    /// Approximate momentary loudness in dBFS (not true BS.1770 LUFS).
    var loudnessDB: Float

    var bass: Float
    var mid: Float
    var treble: Float

    var flux: Float
    /// Decaying pulse `0...1` after an onset.
    var onset: Float
    var onsetDetected: Bool
    /// 0 if unknown; otherwise ~60–180.
    var bpm: Float

    /// 12 pitch classes, C…B, `0...1`.
    var chroma: [Float]
    var pitchClass: Int
    var pitchConfidence: Float

    /// Pearson correlation of L/R, `-1...1`.
    var correlation: Float
    var stereoWidth: Float
    /// Recent mid/side-style XY pairs in `-1...1`.
    var goniometer: [SIMD2<Float>]

    var gain: Float
    var noiseFloor: Float
    var isSilent: Bool

    static let silent = AudioFeatures(
        sampleRate: 48_000,
        timestamp: 0,
        waveform: [Float](repeating: 0, count: DSPConfig.waveformPoints),
        waveformL: [Float](repeating: 0, count: DSPConfig.waveformPoints),
        waveformR: [Float](repeating: 0, count: DSPConfig.waveformPoints),
        fftMagnitudes: [Float](repeating: 0, count: DSPConfig.fftSize / 2),
        bands: [Float](repeating: 0, count: DSPConfig.defaultBandCount),
        bandsPeak: [Float](repeating: 0, count: DSPConfig.defaultBandCount),
        rms: 0,
        peak: 0,
        loudnessDB: -96,
        bass: 0,
        mid: 0,
        treble: 0,
        flux: 0,
        onset: 0,
        onsetDetected: false,
        bpm: 0,
        chroma: [Float](repeating: 0, count: DSPConfig.chromaBins),
        pitchClass: 0,
        pitchConfidence: 0,
        correlation: 1,
        stereoWidth: 0,
        goniometer: [SIMD2<Float>](repeating: .zero, count: DSPConfig.goniometerPoints),
        gain: 1,
        noiseFloor: 1e-5,
        isSilent: true
    )
}

enum DSPConfig {
    static let fftSize = 2048
    static let hopSize = 512
    static let minFrequency: Float = 40
    static let maxFrequency: Float = 16_000
    static let waveformPoints = 256
    static let goniometerPoints = 192
    static let chromaBins = 12
    static let defaultBandCount = 64
    static let allowedBandCounts = [32, 64, 128]

    /// Resample a band array to a fixed length with box averaging / hold.
    static func resample(_ input: [Float], to count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard !input.isEmpty, input.count != count else {
            if input.count == count { return input }
            return [Float](repeating: 0, count: count)
        }
        var output = [Float](repeating: 0, count: count)
        let last = input.count - 1
        for i in 0..<count {
            let src = Float(i) * Float(last) / Float(count - 1)
            let lo = Int(src)
            let hi = min(lo + 1, last)
            let t = src - Float(lo)
            output[i] = input[lo] * (1 - t) + input[hi] * t
        }
        return output
    }
}
