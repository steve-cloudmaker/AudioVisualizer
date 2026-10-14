import XCTest
@testable import AudioVisualizer

final class DSPTests: XCTestCase {
    func testFFTPeaksNear440Hz() throws {
        let fft = try XCTUnwrap(FFTAnalyzer(size: 2048))
        let sr: Float = 48_000
        let freq: Float = 440
        var samples = [Float](repeating: 0, count: 2048)
        for i in 0..<2048 {
            samples[i] = sinf(2 * .pi * freq * Float(i) / sr)
        }
        let mags = fft.magnitudes(from: samples)
        let binHz = sr / 2048
        let expected = Int((freq / binHz).rounded())
        var peakBin = 1
        var peak: Float = 0
        for i in 1..<mags.count / 4 {
            if mags[i] > peak {
                peak = mags[i]
                peakBin = i
            }
        }
        XCTAssertEqual(peakBin, expected, accuracy: 1)
    }

    func testEnvelopeAttacksFasterThanRelease() {
        let env = EnvelopeFollower(count: 1, attack: 0.5, release: 0.1, peakDecay: 0.99)
        env.process([1])
        let afterAttack = env.values[0]
        env.process([0])
        let afterRelease = env.values[0]
        XCTAssertGreaterThan(afterAttack, 0.4)
        XCTAssertGreaterThan(afterRelease, 0)
        XCTAssertLessThan(afterRelease, afterAttack)
    }

    func testOnsetDetectsImpulse() {
        let detector = OnsetDetector(historySize: 20)
        var detected = false
        for _ in 0..<12 {
            _ = detector.process(magnitudes: [Float](repeating: 0.05, count: 32))
        }
        let result = detector.process(magnitudes: [Float](repeating: 4, count: 32))
        detected = result.detected
        XCTAssertTrue(detected)
        XCTAssertGreaterThan(result.onset, 0.5)
    }

    func testChromaIdentifiesA440() throws {
        let analyzer = ChromaAnalyzer()
        let fft = try XCTUnwrap(FFTAnalyzer(size: 2048))
        let sr: Float = 48_000
        var samples = [Float](repeating: 0, count: 2048)
        for i in 0..<2048 {
            samples[i] = sinf(2 * .pi * 440 * Float(i) / sr)
        }
        let mags = fft.magnitudes(from: samples)
        let result = analyzer.process(magnitudes: mags, sampleRate: sr, fftSize: 2048)
        // MIDI 69 = A = class 9
        XCTAssertEqual(result.pitchClass, 9)
        XCTAssertGreaterThan(result.chroma[9], result.chroma[0])
    }

    func testStereoCorrelationMonoAndOutOfPhase() {
        let stereo = StereoAnalyzer(pointCount: 16)
        var left = [Float](repeating: 0, count: 256)
        var right = [Float](repeating: 0, count: 256)
        for i in 0..<256 {
            left[i] = sinf(Float(i) * 0.2)
            right[i] = left[i]
        }
        let mono = left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                stereo.process(left: l.baseAddress!, right: r.baseAddress!, count: 256)
            }
        }
        XCTAssertEqual(mono.correlation, 1, accuracy: 0.02)
        XCTAssertLessThan(mono.width, 0.1)

        for i in 0..<256 { right[i] = -left[i] }
        let flipped = left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                stereo.process(left: l.baseAddress!, right: r.baseAddress!, count: 256)
            }
        }
        XCTAssertEqual(flipped.correlation, -1, accuracy: 0.05)
        XCTAssertGreaterThan(flipped.width, 0.5)
    }

    func testAutoGainBoostsQuietSignalAndGatesSilence() {
        let agc = AutoGain()
        var lastGain: Float = 1
        for _ in 0..<40 {
            lastGain = agc.process(rms: 0.002, bandPeak: 0.002).gain
        }
        XCTAssertGreaterThan(lastGain, 5)
        let silent = agc.process(rms: 0, bandPeak: 0)
        XCTAssertTrue(silent.silent)
    }

    func testFeatureExtractorPlacesEnergyInTrebleFor8kSine() throws {
        let extractor = try XCTUnwrap(FeatureExtractor(bandCount: 64))
        extractor.sensitivity = 1
        let sr: Float = 48_000
        var samples = [Float](repeating: 0, count: DSPConfig.fftSize)
        for i in 0..<samples.count {
            samples[i] = 0.4 * sinf(2 * .pi * 8000 * Float(i) / sr)
        }
        var features = AudioFeatures.silent
        for _ in 0..<24 {
            features = extractor.makeFeatures(mono: samples, sampleRate: sr)
        }
        XCTAssertGreaterThan(features.treble, features.bass)
        XCTAssertFalse(features.bands.allSatisfy { $0 == 0 })
    }

    func testRingBufferWrapCopy() {
        let ring = AudioRingBuffer(capacityFrames: 128)
        var block = [Float](repeating: 0, count: 200 * 2)
        for i in 0..<200 {
            block[i * 2] = Float(i)
            block[i * 2 + 1] = Float(i) + 0.5
        }
        block.withUnsafeBufferPointer { ring.writeInterleaved($0.baseAddress!, frames: 200) }
        var dest = [Float](repeating: 0, count: 64 * 2)
        dest.withUnsafeMutableBufferPointer { _ = ring.copyLatest(frames: 64, dest: $0.baseAddress!) }
        XCTAssertEqual(dest[0], 136, accuracy: 0.01)
        XCTAssertEqual(dest[1], 136.5, accuracy: 0.01)
        XCTAssertEqual(dest[126], 199, accuracy: 0.01)
    }

    func testPresetMixInterpolatesSensitivity() {
        let a = VisualizerPreset.default
        var b = VisualizerPreset.default
        b.sensitivity = 2
        b.hue = 0.6
        let mid = VisualizerPreset.mix(a, b, t: 0.5)
        XCTAssertEqual(mid.sensitivity, 1.5, accuracy: 0.001)
    }

    func testMicrographicSkinMapsBass() {
        let skin = MicrographicSkin.placeholder
        var features = AudioFeatures.silent
        features.bass = 0.8
        let flame = skin.layers.first { $0.id == "flame" }!
        XCTAssertEqual(skin.value(for: flame, features: features), 0.8, accuracy: 0.001)
    }
}
