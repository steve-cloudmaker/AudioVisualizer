import AVFoundation
import Foundation
#if os(macOS)
import CoreAudio
#endif

/// Microphone capture, including wired aux adapters (Lightning/USB-C → 3.5mm) and USB interfaces.
/// iPadOS uses `AVAudioSession` in measurement mode with voice processing off so analog mics stay unprocessed.
final class AudioCapture: @unchecked Sendable {
    enum Status: Equatable {
        case idle
        case unauthorized
        case running
        case interrupted
        case failed(String)
    }

    let ringBuffer = AudioRingBuffer()

    private let engine = AVAudioEngine()
    private let convertScratch: UnsafeMutablePointer<Float>
    private let convertScratchFrames = 4096
    private var tapInstalled = false
    private var observers: [NSObjectProtocol] = []
    private var recovering = false
#if os(macOS)
    private var hardwareListener: AudioObjectPropertyListenerBlock?
#endif

    private let lock = NSLock()
    private var _status: Status = .idle
    private var _sampleRate: Double = 48_000
    private var _channelCount: Int = 1
    private var _inputs: [AudioInputInfo] = []
    private var _currentInput: AudioInputInfo?
    private var _inputGain: Float = 1
    private var _inputGainSettable = false

    var status: Status {
        lock.lock(); defer { lock.unlock() }
        return _status
    }

    var sampleRate: Double {
        lock.lock(); defer { lock.unlock() }
        return _sampleRate
    }

    var channelCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _channelCount
    }

    var inputs: [AudioInputInfo] {
        lock.lock(); defer { lock.unlock() }
        return _inputs
    }

    var currentInput: AudioInputInfo? {
        lock.lock(); defer { lock.unlock() }
        return _currentInput
    }

    var inputGain: Float {
        lock.lock(); defer { lock.unlock() }
        return _inputGain
    }

    var inputGainSettable: Bool {
        lock.lock(); defer { lock.unlock() }
        return _inputGainSettable
    }

    var onFormatChange: ((Double, Int) -> Void)?
    var onStatusChange: ((Status) -> Void)?
    var onInputsChange: (() -> Void)?

    init() {
        convertScratch = .allocate(capacity: convertScratchFrames * 2)
        convertScratch.initialize(repeating: 0, count: convertScratchFrames * 2)
    }

    deinit {
        stop()
        convertScratch.deinitialize(count: convertScratchFrames * 2)
        convertScratch.deallocate()
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() throws {
        #if os(iOS)
        try configureSession()
        #endif
        try installTap()
        engine.prepare()
        try engine.start()
        refreshInputs(preferNewWired: true)
        try applyPreferredInput(preferNewWired: true)
        setStatus(.running)
        listenForInterruptions()
        listenForHardwareChanges()
    }

    func stop() {
        removeHardwareListener()
        removeTap()
        if engine.isRunning {
            engine.stop()
        }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
        if status != .unauthorized {
            setStatus(.idle)
        }
    }

    func selectInput(_ info: AudioInputInfo) throws {
        lock.lock()
        _currentInput = info
        lock.unlock()
        try applyInput(info)
        refreshInputs(preferNewWired: false)
        onInputsChange?()
    }

    func setInputGain(_ value: Float) {
        let clamped = max(0, min(1, value))
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if session.isInputGainSettable {
            try? session.setInputGain(clamped)
        }
        #endif
        lock.lock()
        _inputGain = clamped
        lock.unlock()
        onInputsChange?()
    }

    // MARK: - Session (iPadOS / iOS)

    #if os(iOS)
    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        // `.measurement` keeps analog / USB mics unprocessed. Voice Isolation wrecks FFT.
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth]
        )
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(256.0 / 48_000.0)
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true)

        let input = engine.inputNode
        if input.isVoiceProcessingEnabled {
            try input.setVoiceProcessingEnabled(false)
        }
        if #available(iOS 17.0, *) {
            input.isVoiceProcessingBypassed = true
        }
    }
    #endif

    // MARK: - Engine

    private func installTap() throws {
        let input = engine.inputNode
        #if os(iOS)
        if input.isVoiceProcessingEnabled {
            try input.setVoiceProcessingEnabled(false)
        }
        #endif

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError.noInput
        }

        lock.lock()
        _sampleRate = format.sampleRate
        _channelCount = Int(format.channelCount)
        lock.unlock()

        removeTap()
        input.installTap(onBus: 0, bufferSize: 256, format: format) { [weak self] buffer, _ in
            self?.ingest(buffer)
        }
        tapInstalled = true
        onFormatChange?(format.sampleRate, Int(format.channelCount))
    }

    private func removeTap() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    private func ingest(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let chunk = min(frames, convertScratchFrames)
        let ch = Int(buffer.format.channelCount)

        if ch >= 2 {
            let left = channels[0]
            let right = channels[1]
            for i in 0..<chunk {
                convertScratch[i * 2] = left[i]
                convertScratch[i * 2 + 1] = right[i]
            }
        } else {
            let mono = channels[0]
            for i in 0..<chunk {
                let s = mono[i]
                convertScratch[i * 2] = s
                convertScratch[i * 2 + 1] = s
            }
        }
        ringBuffer.writeInterleaved(convertScratch, frames: chunk)

        let sr = buffer.format.sampleRate
        if abs(sr - sampleRate) > 1 {
            lock.lock()
            _sampleRate = sr
            _channelCount = ch
            lock.unlock()
            onFormatChange?(sr, ch)
        }
    }

    // MARK: - Input selection

    private func refreshInputs(preferNewWired: Bool) {
        let listed = listInputs()
        lock.lock()
        _inputs = listed
        if let current = InputRouter.preferred(
            among: listed,
            previousID: _currentInput?.id,
            preferNewWired: preferNewWired
        ) {
            _currentInput = current
        }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        _inputGainSettable = session.isInputGainSettable
        _inputGain = session.inputGain
        #endif
        lock.unlock()
        onInputsChange?()
    }

    private func applyPreferredInput(preferNewWired: Bool) throws {
        let listed = inputs
        let previous = currentInput?.id
        guard let chosen = InputRouter.preferred(
            among: listed,
            previousID: previous,
            preferNewWired: preferNewWired
        ) else { return }
        try applyInput(chosen)
    }

    private func applyInput(_ info: AudioInputInfo) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if let port = session.availableInputs?.first(where: { $0.uid == info.id }) {
            try session.setPreferredInput(port)
        }
        #elseif os(macOS)
        if let deviceID = UInt32(info.id) {
            try setMacInputDevice(deviceID)
        }
        #endif
        if engine.isRunning {
            try installTap()
        }
    }

    private func listInputs() -> [AudioInputInfo] {
        #if os(iOS)
        return listIOSInputs()
        #elseif os(macOS)
        return listMacInputs()
        #else
        return []
        #endif
    }

    #if os(iOS)
    private func listIOSInputs() -> [AudioInputInfo] {
        let session = AVAudioSession.sharedInstance()
        return (session.availableInputs ?? []).map { port in
            AudioInputInfo(
                id: port.uid,
                name: port.portName,
                kind: InputRouter.kind(portTypeRaw: port.portType.rawValue)
            )
        }
    }
    #endif

    #if os(macOS)
    private func listMacInputs() -> [AudioInputInfo] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &devices
        ) == noErr else { return [] }

        return devices.compactMap { deviceID in
            guard inputStreamCount(deviceID) > 0 else { return nil }
            return AudioInputInfo(
                id: String(deviceID),
                name: deviceName(deviceID) ?? "Input \(deviceID)",
                kind: InputRouter.kind(transport: transportType(deviceID))
            )
        }
    }

    private func inputStreamCount(_ device: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &dataSize) == noErr else { return 0 }
        return Int(dataSize) / MemoryLayout<AudioStreamID>.size
    }

    private func deviceName(_ device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, ptr)
        }
        guard status == noErr else { return nil }
        return name as String
    }

    private func transportType(_ device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else {
            return 0
        }
        return transport
    }

    private func setMacInputDevice(_ deviceID: AudioDeviceID) throws {
        engine.prepare()
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw CaptureError.noInput
        }
        var id = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            size
        )
        if status != noErr {
            throw CaptureError.deviceSelectFailed
        }
    }
    #endif

    // MARK: - Interruptions / routes

    private func listenForInterruptions() {
        guard observers.isEmpty else { return }

        #if os(iOS)
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                self?.handleInterruption(note)
            }
        )
        observers.append(
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
                self?.handleRouteChange(note)
            }
        )
        observers.append(
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
                self?.recoverEngine(preferNewWired: false)
            }
        )
        #endif

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: engine,
                queue: .main
            ) { [weak self] _ in
                self?.recoverEngine(preferNewWired: false)
            }
        )
    }

    #if os(iOS)
    private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            engine.pause()
            setStatus(.interrupted)
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                recoverEngine(preferNewWired: false)
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard
            let info = note.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        switch reason {
        case .newDeviceAvailable:
            recoverEngine(preferNewWired: true)
        case .oldDeviceUnavailable, .categoryChange, .override, .wakeFromSleep, .routeConfigurationChange:
            recoverEngine(preferNewWired: false)
        default:
            break
        }
    }
    #endif

    private func listenForHardwareChanges() {
        #if os(macOS)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.recoverEngine(preferNewWired: true)
            }
        }
        hardwareListener = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        #endif
    }

    private func removeHardwareListener() {
        #if os(macOS)
        guard hardwareListener != nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if let hardwareListener {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                hardwareListener
            )
        }
        hardwareListener = nil
        #endif
    }

    private func recoverEngine(preferNewWired: Bool) {
        guard !recovering else { return }
        recovering = true
        defer { recovering = false }
        do {
            #if os(iOS)
            try configureSession()
            #endif
            refreshInputs(preferNewWired: preferNewWired)
            try applyPreferredInput(preferNewWired: preferNewWired)
            try installTap()
            if !engine.isRunning {
                try engine.start()
            }
            setStatus(.running)
        } catch {
            setStatus(.failed(error.localizedDescription))
        }
    }

    private func setStatus(_ status: Status) {
        lock.lock()
        _status = status
        lock.unlock()
        onStatusChange?(status)
    }

    enum CaptureError: LocalizedError {
        case noInput
        case deviceSelectFailed

        var errorDescription: String? {
            switch self {
            case .noInput:
                return "No microphone input is available."
            case .deviceSelectFailed:
                return "Could not switch to the selected microphone."
            }
        }
    }
}
