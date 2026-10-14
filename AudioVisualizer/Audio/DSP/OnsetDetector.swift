import Foundation

/// SuperFlux-style positive spectral difference against an adaptive mean threshold.
final class OnsetDetector {
    private var previous: [Float] = []
    private var fluxHistory: [Float] = []
    private let historySize: Int
    private var cooldown: Float = 0

    init(historySize: Int = 43) {
        self.historySize = historySize
    }

    func process(magnitudes: [Float]) -> (flux: Float, onset: Float, detected: Bool) {
        var flux: Float = 0
        if previous.count == magnitudes.count {
            for i in 0..<magnitudes.count {
                let d = magnitudes[i] - previous[i]
                if d > 0 { flux += d }
            }
        }
        previous = magnitudes

        fluxHistory.append(flux)
        if fluxHistory.count > historySize {
            fluxHistory.removeFirst()
        }
        let mean = fluxHistory.reduce(0, +) / Float(max(fluxHistory.count, 1))
        var variance: Float = 0
        for v in fluxHistory {
            let d = v - mean
            variance += d * d
        }
        variance /= Float(max(fluxHistory.count, 1))
        let thresh = mean + 1.4 * sqrtf(variance) + 1e-5

        cooldown = max(0, cooldown - 1)
        let detected = flux > thresh && flux > mean * 1.35 && cooldown == 0 && fluxHistory.count > 8
        if detected {
            cooldown = 6
        }
        let pulse: Float = detected ? 1 : max(0, (cooldown / 6) * 0.7)
        return (flux, pulse, detected)
    }
}
