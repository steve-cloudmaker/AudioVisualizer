import Foundation

/// Median inter-onset interval → BPM. Ignores intervals outside 60–180 so room noise doesn't invent a tempo.
final class TempoTracker {
    private var times: [TimeInterval] = []
    private let maxHits = 12
    private(set) var bpm: Float = 0

    func ingest(onset: Bool, time: TimeInterval) -> Float {
        if onset {
            times.append(time)
            if times.count > maxHits {
                times.removeFirst(times.count - maxHits)
            }
        }
        guard times.count >= 4 else {
            bpm = 0
            return 0
        }
        var intervals: [Double] = []
        for i in 1..<times.count {
            let dt = times[i] - times[i - 1]
            if dt >= 60.0 / 180.0 && dt <= 60.0 / 60.0 {
                intervals.append(dt)
            }
        }
        guard intervals.count >= 3 else {
            bpm = 0
            return 0
        }
        intervals.sort()
        let median = intervals[intervals.count / 2]
        bpm = Float(60.0 / median)
        return bpm
    }

    func reset() {
        times.removeAll()
        bpm = 0
    }
}
