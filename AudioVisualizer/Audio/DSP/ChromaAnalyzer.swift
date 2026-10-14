import Foundation

/// Maps FFT magnitudes onto 12 pitch classes (C = 0 … B = 11).
final class ChromaAnalyzer {
    func process(magnitudes: [Float], sampleRate: Float, fftSize: Int) -> (chroma: [Float], pitchClass: Int, confidence: Float) {
        var chroma = [Float](repeating: 0, count: DSPConfig.chromaBins)
        let binHz = sampleRate / Float(fftSize)
        for i in 1..<magnitudes.count {
            let freq = Float(i) * binHz
            if freq < 55 || freq > 4_000 { continue }
            let midi = 69 + 12 * log2f(max(freq, 1) / 440)
            let classIndex = positiveMod(Int(midi.rounded()), 12)
            chroma[classIndex] += magnitudes[i] * magnitudes[i]
        }
        let total = chroma.reduce(0, +)
        if total > 1e-12 {
            for i in 0..<chroma.count {
                chroma[i] = sqrtf(chroma[i] / total)
            }
        }
        var best = 0
        var bestVal: Float = 0
        for i in 0..<chroma.count where chroma[i] > bestVal {
            bestVal = chroma[i]
            best = i
        }
        return (chroma, best, bestVal)
    }

    private func positiveMod(_ value: Int, _ modulus: Int) -> Int {
        let r = value % modulus
        return r >= 0 ? r : r + modulus
    }
}
