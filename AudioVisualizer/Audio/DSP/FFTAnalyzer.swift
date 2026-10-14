import Accelerate
import Foundation

/// Real FFT of `DSPConfig.fftSize` samples using Accelerate. Output is linear-frequency magnitude.
final class FFTAnalyzer {
    let size: Int
    private let half: Int
    private let fft: vDSP.FFT<DSPSplitComplex>
    private var window: [Float]
    private var windowed: [Float]
    private let realp: UnsafeMutablePointer<Float>
    private let imagp: UnsafeMutablePointer<Float>
    private var magnitudesStorage: [Float]

    init?(size: Int = DSPConfig.fftSize) {
        self.size = size
        half = size / 2
        let log2n = vDSP_Length(log2(Double(size)))
        guard let fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self) else {
            return nil
        }
        self.fft = fft
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        windowed = [Float](repeating: 0, count: size)
        realp = .allocate(capacity: half)
        imagp = .allocate(capacity: half)
        realp.initialize(repeating: 0, count: half)
        imagp.initialize(repeating: 0, count: half)
        magnitudesStorage = [Float](repeating: 0, count: half)
    }

    deinit {
        realp.deinitialize(count: half)
        imagp.deinitialize(count: half)
        realp.deallocate()
        imagp.deallocate()
    }

    /// - Parameter samples: `size` mono floats.
    /// - Returns: `size/2` magnitudes (not dB). Bin 0 is DC.
    @discardableResult
    func magnitudes(from samples: UnsafePointer<Float>) -> [Float] {
        let input = UnsafeBufferPointer(start: samples, count: size)
        vDSP.multiply(window, input, result: &windowed)

        var split = DSPSplitComplex(realp: realp, imagp: imagp)
        windowed.withUnsafeBytes { raw in
            let complex = raw.bindMemory(to: DSPComplex.self)
            guard let base = complex.baseAddress else { return }
            vDSP_ctoz(base, 2, &split, 1, vDSP_Length(half))
        }
        fft.forward(input: split, output: &split)
        vDSP.squareMagnitudes(split, result: &magnitudesStorage)
        var count = Int32(magnitudesStorage.count)
        var roots = [Float](repeating: 0, count: magnitudesStorage.count)
        vvsqrtf(&roots, &magnitudesStorage, &count)
        magnitudesStorage = roots
        if magnitudesStorage.count > 2 {
            magnitudesStorage[0] = 0
            magnitudesStorage[1] *= 0.25
        }
        return magnitudesStorage
    }

    func magnitudes(from samples: [Float]) -> [Float] {
        samples.withUnsafeBufferPointer { buf in
            magnitudes(from: buf.baseAddress!)
        }
    }
}
