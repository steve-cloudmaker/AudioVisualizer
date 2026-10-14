import Foundation

/// Per-band fast-attack / slow-release follower plus peak hold.
/// This is what makes an RTA look like an RTA instead of noise.
final class EnvelopeFollower {
    private(set) var values: [Float]
    private(set) var peaks: [Float]
    var attack: Float
    var release: Float
    var peakDecay: Float

    init(
        count: Int,
        attack: Float = 0.45,
        release: Float = 0.08,
        peakDecay: Float = 0.97
    ) {
        values = [Float](repeating: 0, count: count)
        peaks = [Float](repeating: 0, count: count)
        self.attack = attack
        self.release = release
        self.peakDecay = peakDecay
    }

    func resize(count: Int) {
        guard count != values.count else { return }
        values = [Float](repeating: 0, count: count)
        peaks = [Float](repeating: 0, count: count)
    }

    func process(_ input: [Float]) {
        let n = min(values.count, input.count)
        for i in 0..<n {
            let x = input[i]
            if x > values[i] {
                values[i] += (x - values[i]) * attack
            } else {
                values[i] += (x - values[i]) * release
            }
            peaks[i] = max(peaks[i] * peakDecay, values[i])
        }
    }
}
