import Foundation
import os

/// Stereo interleaved float ring. Audio writes, analysis copies the latest FFT window.
/// A short unfair lock is used instead of a lock-free SPSC so wrap copies stay consistent.
final class AudioRingBuffer: @unchecked Sendable {
    let channels = 2
    private let frameCapacity: Int
    private let storage: UnsafeMutablePointer<Float>
    private var writeFrame: Int = 0
    private let lock = OSAllocatedUnfairLock()

    init(capacityFrames: Int = 48_000 * 2) {
        frameCapacity = capacityFrames
        storage = .allocate(capacity: capacityFrames * 2)
        storage.initialize(repeating: 0, count: capacityFrames * 2)
    }

    deinit {
        storage.deinitialize(count: frameCapacity * 2)
        storage.deallocate()
    }

    var publishedFrames: Int {
        lock.withLock { writeFrame }
    }

    func writeInterleaved(_ src: UnsafePointer<Float>, frames: Int) {
        guard frames > 0 else { return }
        let floatCount = MemoryLayout<Float>.size
        lock.withLock {
            var remaining = frames
            var srcOffset = 0
            var pos = writeFrame % frameCapacity
            while remaining > 0 {
                let room = frameCapacity - pos
                let n = min(remaining, room)
                memcpy(
                    storage.advanced(by: pos * 2),
                    src.advanced(by: srcOffset * 2),
                    n * 2 * floatCount
                )
                pos = (pos + n) % frameCapacity
                srcOffset += n
                remaining -= n
            }
            writeFrame += frames
        }
    }

    /// Copies the most recent `frames` of interleaved stereo into `dest` (`frames * 2` floats).
    @discardableResult
    func copyLatest(frames: Int, dest: UnsafeMutablePointer<Float>) -> Bool {
        let floatCount = MemoryLayout<Float>.size
        return lock.withLock {
            guard writeFrame >= frames, frames > 0 else { return false }
            let start = writeFrame - frames
            var remaining = frames
            var destOffset = 0
            var pos = start % frameCapacity
            if pos < 0 { pos += frameCapacity }
            while remaining > 0 {
                let room = frameCapacity - pos
                let n = min(remaining, room)
                memcpy(
                    dest.advanced(by: destOffset * 2),
                    storage.advanced(by: pos * 2),
                    n * 2 * floatCount
                )
                pos = (pos + n) % frameCapacity
                destOffset += n
                remaining -= n
            }
            return true
        }
    }
}
