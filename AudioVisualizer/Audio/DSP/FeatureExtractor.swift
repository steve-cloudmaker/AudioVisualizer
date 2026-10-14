import Accelerate
import Foundation
import QuartzCore

/// Owns the analysis loop: ring → FFT → log bands → envelopes → onset/chroma/stereo/AGC → `FeatureBus`.
final class FeatureExtractor: @unchecked Sendable {
    private let fft: FFTAnalyzer
    private let envelopes: EnvelopeFollower
    private let onset = OnsetDetector()
    private let chroma = ChromaAnalyzer()
    private let stereo = StereoAnalyzer()
    private let agc = AutoGain()
    private let tempo = TempoTracker()

    private var bandCount: Int
    private var binStarts: [Int] = []
    private var binEnds: [Int] = []
    private var mappedSampleRate: Float = 0

    private let fftFrames: Int
    private let hopFrames: Int
    private var scratch: UnsafeMutablePointer<Float>
    private var left: [Float]
    private var right: [Float]
    private var mono: [Float]

    private let queue = DispatchQueue(label: "studio.audiovisualizer.analysis", qos: .userInteractive)
    private var running = false
    private var lastProcessedFrame: Int = 0

    var sensitivity: Float = 1
    var sampleRate: Double = 48_000

    init?(bandCount: Int = DSPConfig.defaultBandCount) {
        guard let fft = FFTAnalyzer() else { return nil }
        self.fft = fft
        fftFrames = DSPConfig.fftSize
        hopFrames = DSPConfig.hopSize
        self.bandCount = bandCount
        envelopes = EnvelopeFollower(count: bandCount)
        scratch = .allocate(capacity: fftFrames * 2)
        scratch.initialize(repeating: 0, count: fftFrames * 2)
        left = [Float](repeating: 0, count: fftFrames)
        right = [Float](repeating: 0, count: fftFrames)
        mono = [Float](repeating: 0, count: fftFrames)
        rebuildBandMap(sampleRate: Float(sampleRate))
    }

    deinit {
        stop()
        scratch.deinitialize(count: fftFrames * 2)
        scratch.deallocate()
    }

    func setBandCount(_ count: Int) {
        let clamped = DSPConfig.allowedBandCounts.contains(count) ? count : DSPConfig.defaultBandCount
        guard clamped != bandCount else { return }
        bandCount = clamped
        envelopes.resize(count: clamped)
        rebuildBandMap(sampleRate: Float(sampleRate))
    }

    func start(ring: AudioRingBuffer, bus: FeatureBus) {
        running = true
        lastProcessedFrame = 0
        queue.async { [weak self] in
            while let self, self.running {
                self.tick(ring: ring, bus: bus)
            }
        }
    }

    func stop() {
        running = false
    }

    /// Testable one-shot: `interleaved` must contain at least `fftSize` stereo frames.
    func makeFeatures(interleaved: UnsafePointer<Float>, frames: Int, sampleRate: Float, timestamp: TimeInterval) -> AudioFeatures {
        let n = min(frames, fftFrames)
        for i in 0..<n {
            left[i] = interleaved[i * 2]
            right[i] = interleaved[i * 2 + 1]
            mono[i] = (left[i] + right[i]) * 0.5
        }
        if n < fftFrames {
            for i in n..<fftFrames {
                left[i] = 0
                right[i] = 0
                mono[i] = 0
            }
        }
        return analyze(sampleRate: sampleRate, timestamp: timestamp)
    }

    func makeFeatures(mono samples: [Float], sampleRate: Float, timestamp: TimeInterval = 0) -> AudioFeatures {
        var interleaved = [Float](repeating: 0, count: max(samples.count, fftFrames) * 2)
        let n = min(samples.count, fftFrames)
        for i in 0..<n {
            interleaved[i * 2] = samples[i]
            interleaved[i * 2 + 1] = samples[i]
        }
        return interleaved.withUnsafeBufferPointer { buf in
            makeFeatures(interleaved: buf.baseAddress!, frames: n, sampleRate: sampleRate, timestamp: timestamp)
        }
    }

    // MARK: - Loop

    private func tick(ring: AudioRingBuffer, bus: FeatureBus) {
        let published = ring.publishedFrames
        guard published >= fftFrames else {
            usleep(2_000)
            return
        }
        var due = lastProcessedFrame + hopFrames
        if lastProcessedFrame == 0 {
            due = published
        }
        if published < due {
            usleep(1_500)
            return
        }
        if published - due > hopFrames * 6 {
            due = published
        }
        lastProcessedFrame = due
        guard ring.copyLatest(frames: fftFrames, dest: scratch) else {
            usleep(1_500)
            return
        }
        let sr = Float(sampleRate)
        let features = makeFeatures(interleaved: scratch, frames: fftFrames, sampleRate: sr, timestamp: CACurrentMediaTime())
        bus.publish(features)
    }

    private func analyze(sampleRate: Float, timestamp: TimeInterval) -> AudioFeatures {
        if abs(sampleRate - mappedSampleRate) > 1 {
            rebuildBandMap(sampleRate: sampleRate)
        }

        var peak: Float = 0
        var sumSq: Float = 0
        for i in 0..<fftFrames {
            let s = mono[i]
            sumSq += s * s
            let a = fabsf(s)
            if a > peak { peak = a }
        }
        let rms = sqrtf(sumSq / Float(fftFrames))

        let mags = fft.magnitudes(from: mono)
        var rawBands = mapLogBands(mags, sampleRate: sampleRate)
        // Convert to a loosely normalized dB-ish 0...1 before envelopes.
        for i in 0..<rawBands.count {
            let db = 20 * log10f(rawBands[i] + 1e-8)
            rawBands[i] = max(0, min(1, (db + 80) / 80))
        }
        envelopes.process(rawBands)

        let (flux, onsetPulse, detected) = onset.process(magnitudes: mags)
        let chromaResult = chroma.process(magnitudes: mags, sampleRate: sampleRate, fftSize: fftFrames)
        let stereoResult = left.withUnsafeBufferPointer { lBuf in
            right.withUnsafeBufferPointer { rBuf in
                stereo.process(left: lBuf.baseAddress!, right: rBuf.baseAddress!, count: fftFrames)
            }
        }

        let bandPeak = envelopes.values.max() ?? 0
        let (autoGain, silent) = agc.process(rms: rms, bandPeak: bandPeak)
        let bpm = tempo.ingest(onset: detected && !silent, time: timestamp)
        let gain = autoGain * max(0.2, min(3, sensitivity))

        var bands = envelopes.values
        var peaks = envelopes.peaks
        for i in 0..<bands.count {
            bands[i] = silent ? bands[i] * 0.92 : max(0, min(1, bands[i] * gain))
            peaks[i] = silent ? peaks[i] * 0.92 : max(0, min(1, peaks[i] * gain))
        }

        let bass = mean(bands, startFrac: 0, endFrac: 0.18) 
        let mid = mean(bands, startFrac: 0.18, endFrac: 0.55)
        let treble = mean(bands, startFrac: 0.55, endFrac: 1)

        let waveform = downsample(mono, to: DSPConfig.waveformPoints)
        let waveformL = downsample(left, to: DSPConfig.waveformPoints)
        let waveformR = downsample(right, to: DSPConfig.waveformPoints)

        let loudnessDB = 20 * log10f(max(rms * gain, 1e-8))

        return AudioFeatures(
            sampleRate: sampleRate,
            timestamp: timestamp,
            waveform: waveform,
            waveformL: waveformL,
            waveformR: waveformR,
            fftMagnitudes: mags,
            bands: bands,
            bandsPeak: peaks,
            rms: max(0, min(1, rms * gain * 2.5)),
            peak: max(0, min(1, peak * gain)),
            loudnessDB: max(-96, min(0, loudnessDB)),
            bass: max(0, min(1, bass)),
            mid: max(0, min(1, mid)),
            treble: max(0, min(1, treble)),
            flux: flux,
            onset: silent ? 0 : onsetPulse,
            onsetDetected: silent ? false : detected,
            bpm: silent ? 0 : bpm,
            chroma: chromaResult.chroma,
            pitchClass: chromaResult.pitchClass,
            pitchConfidence: chromaResult.confidence,
            correlation: stereoResult.correlation,
            stereoWidth: stereoResult.width,
            goniometer: stereoResult.points,
            gain: gain,
            noiseFloor: agc.noiseFloor,
            isSilent: silent
        )
    }

    private func rebuildBandMap(sampleRate: Float) {
        mappedSampleRate = sampleRate
        let nyquist = sampleRate / 2
        let maxF = min(DSPConfig.maxFrequency, nyquist - 10)
        let minF = DSPConfig.minFrequency
        let bins = fft.size / 2
        let hzPerBin = sampleRate / Float(fft.size)
        binStarts = [Int](repeating: 0, count: bandCount)
        binEnds = [Int](repeating: 0, count: bandCount)
        for band in 0..<bandCount {
            let fracLo = Float(band) / Float(bandCount)
            let fracHi = Float(band + 1) / Float(bandCount)
            let fLo = minF * powf(maxF / minF, fracLo)
            let fHi = minF * powf(maxF / minF, fracHi)
            var start = Int(fLo / hzPerBin)
            var end = Int(ceilf(fHi / hzPerBin))
            start = min(max(1, start), bins - 1)
            end = min(max(start + 1, end), bins)
            binStarts[band] = start
            binEnds[band] = end
        }
    }

    private func mapLogBands(_ magnitudes: [Float], sampleRate: Float) -> [Float] {
        if binStarts.count != bandCount || abs(sampleRate - mappedSampleRate) > 1 {
            rebuildBandMap(sampleRate: sampleRate)
        }
        var bands = [Float](repeating: 0, count: bandCount)
        for b in 0..<bandCount {
            let start = binStarts[b]
            let end = binEnds[b]
            var sum: Float = 0
            let span = max(1, end - start)
            for i in start..<end {
                sum += magnitudes[i]
            }
            bands[b] = sum / Float(span)
        }
        return bands
    }

    private func mean(_ values: [Float], startFrac: Float, endFrac: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        let start = Int(startFrac * Float(values.count))
        let end = min(values.count, max(start + 1, Int(endFrac * Float(values.count))))
        var s: Float = 0
        for i in start..<end { s += values[i] }
        return s / Float(end - start)
    }

    private func downsample(_ input: [Float], to count: Int) -> [Float] {
        guard count > 0, !input.isEmpty else { return [Float](repeating: 0, count: count) }
        var out = [Float](repeating: 0, count: count)
        let step = Float(input.count) / Float(count)
        for i in 0..<count {
            let src = Int(Float(i) * step)
            out[i] = input[min(src, input.count - 1)]
        }
        return out
    }
}
