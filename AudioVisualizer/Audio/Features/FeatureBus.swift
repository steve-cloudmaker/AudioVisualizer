import Foundation

/// Latest-wins feature bus. The audio thread never touches this; analysis publishes, render snapshots.
final class FeatureBus: @unchecked Sendable {
    private let lock = NSLock()
    private var current = AudioFeatures.silent

    func publish(_ features: AudioFeatures) {
        lock.lock()
        current = features
        lock.unlock()
    }

    func snapshot() -> AudioFeatures {
        lock.lock()
        defer { lock.unlock() }
        return current
    }
}
