import Foundation

/// Adaptive gain so a laptop-speaker whisper and a kitchen speaker both fill 0...1.
final class AutoGain {
    private(set) var noiseFloor: Float = 1e-5
    private(set) var peakEnv: Float = 1e-4
    var target: Float = 0.65

    func process(rms: Float, bandPeak: Float) -> (gain: Float, silent: Bool) {
        let level = max(rms, bandPeak)
        if level < noiseFloor {
            noiseFloor = level * 0.25 + noiseFloor * 0.75
        } else {
            noiseFloor = min(noiseFloor * 1.0008 + 1e-9, level)
        }
        noiseFloor = max(noiseFloor, 1e-6)

        if level > peakEnv {
            peakEnv += (level - peakEnv) * 0.18
        } else {
            peakEnv += (level - peakEnv) * 0.003
        }

        let silent = level < max(noiseFloor * 6, 2e-4)
        let gain = min(48, target / max(peakEnv, 1e-6))
        return (gain, silent)
    }

    func reset() {
        noiseFloor = 1e-5
        peakEnv = 1e-4
    }
}
