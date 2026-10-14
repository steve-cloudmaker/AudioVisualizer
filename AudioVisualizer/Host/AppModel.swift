import Combine
import Foundation
import QuartzCore
#if os(iOS)
import UIKit
#endif

@MainActor
final class AppModel: ObservableObject {
    let capture = AudioCapture()
    let bus = FeatureBus()
    let registry = SceneRegistry.default
    let presets = PresetStore()

    private let extractor: FeatureExtractor?
    private var scene: any VisualizerScene
    private var shuffleCooldown: TimeInterval = 0
    private var lastFeatureTime: TimeInterval = 0
    private var interpolatingFrom: VisualizerPreset?
    private var interpolatingTo: VisualizerPreset?
    private var interpolateStart: TimeInterval = 0
    private let interpolateDuration: TimeInterval = 1.2

    @Published var selectedSceneID: String
    @Published var preset: VisualizerPreset
    @Published var chromeVisible = true
    @Published var status: AudioCapture.Status = .idle
    @Published var permissionDenied = false
    @Published var running = false
    @Published var inputs: [AudioInputInfo] = []
    @Published var currentInputID: String = ""
    @Published var currentInputName: String = "Microphone"
    @Published var inputGain: Float = 1
    @Published var inputGainSettable = false
    @Published var externalDisplayConnected = false

    private var hideTask: Task<Void, Never>?
    private let externalDisplay = ExternalDisplayController()

    init() {
        extractor = FeatureExtractor()
        let initial = VisualizerPreset.default
        preset = initial
        selectedSceneID = initial.sceneID
        scene = SceneFactory.make(initial.sceneID)
        capture.onStatusChange = { [weak self] status in
            Task { @MainActor in
                self?.status = status
            }
        }
        capture.onInputsChange = { [weak self] in
            Task { @MainActor in
                self?.syncInputs()
            }
        }
        let extractorRef = extractor
        capture.onFormatChange = { sampleRate, _ in
            extractorRef?.sampleRate = sampleRate
        }
    }

    var currentScene: any VisualizerScene { scene }

    func startIfNeeded() async {
        let granted = await capture.requestPermission()
        permissionDenied = !granted
        guard granted else {
            status = .unauthorized
            return
        }
        do {
            try capture.start()
            extractor?.sensitivity = preset.sensitivity
            extractor?.setBandCount(preset.bandCount)
            extractor?.sampleRate = capture.sampleRate
            extractor?.start(ring: capture.ringBuffer, bus: bus)
            running = true
            syncInputs()
            externalDisplay.start(model: self)
            bumpChrome()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func stop() {
        extractor?.stop()
        capture.stop()
        externalDisplay.stop()
        running = false
    }

    func selectScene(_ id: String) {
        guard id != selectedSceneID else { return }
        scene.detach()
        selectedSceneID = id
        scene = SceneFactory.make(id)
        preset.sceneID = id
        bumpChrome()
    }

    func applyPreset(_ next: VisualizerPreset, animated: Bool) {
        if animated {
            interpolatingFrom = preset
            interpolatingTo = next
            interpolateStart = CACurrentMediaTime()
        } else {
            interpolatingFrom = nil
            interpolatingTo = nil
            preset = next
            selectedSceneID = next.sceneID
        }
        if next.sceneID != selectedSceneID {
            selectScene(next.sceneID)
        }
        extractor?.sensitivity = next.sensitivity
        extractor?.setBandCount(next.bandCount)
        presets.selectedName = next.name
        bumpChrome()
    }

    func setSensitivity(_ value: Float) {
        preset.sensitivity = value
        extractor?.sensitivity = value
        bumpChrome()
    }

    func selectInput(_ info: AudioInputInfo) {
        do {
            try capture.selectInput(info)
            syncInputs()
        } catch {
            status = .failed(error.localizedDescription)
        }
        bumpChrome()
    }

    func setInputGain(_ value: Float) {
        capture.setInputGain(value)
        inputGain = value
        bumpChrome()
    }

    func fire(_ event: SceneEvent) {
        scene.handle(event)
        bumpChrome()
    }

    private func syncInputs() {
        inputs = capture.inputs
        currentInputID = capture.currentInput?.id ?? ""
        let info = capture.currentInput
        if let info {
            currentInputName = "\(info.shortLabel)  \(info.name)"
        } else {
            currentInputName = "Microphone"
        }
        inputGain = capture.inputGain
        inputGainSettable = capture.inputGainSettable
    }

    func saveCurrentPreset() {
        var stored = preset
        stored.sceneID = selectedSceneID
        presets.save(stored)
    }

    func bumpChrome() {
        chromeVisible = true
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.chromeVisible = false
        }
    }

    /// Called from scene views once per display frame.
    func tickFrame() -> (features: AudioFeatures, dt: TimeInterval, preset: VisualizerPreset, scene: any VisualizerScene) {
        let features = bus.snapshot()
        let now = features.timestamp == 0 ? CACurrentMediaTime() : features.timestamp
        let dt = lastFeatureTime == 0 ? 1.0 / 60.0 : max(1.0 / 120.0, min(0.05, now - lastFeatureTime))
        lastFeatureTime = now

        if let from = interpolatingFrom, let to = interpolatingTo {
            let t = Float((CACurrentMediaTime() - interpolateStart) / interpolateDuration)
            if t >= 1 {
                preset = to
                interpolatingFrom = nil
                interpolatingTo = nil
                extractor?.sensitivity = to.sensitivity
                extractor?.setBandCount(to.bandCount)
            } else {
                preset = VisualizerPreset.mix(from, to, t: t)
                extractor?.sensitivity = preset.sensitivity
            }
        }

        if preset.shuffleOnBeat, features.onsetDetected, shuffleCooldown <= 0 {
            let ids = registry.all.map(\.id).filter { $0 != selectedSceneID }
            if let next = ids.randomElement() {
                selectScene(next)
                shuffleCooldown = 4
            }
        }
        shuffleCooldown = max(0, shuffleCooldown - dt)

        #if os(iOS)
        if preset.hapticsEnabled, features.onsetDetected {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        #endif

        scene.update(features: features, dt: dt, preset: preset)
        return (features, dt, preset, scene)
    }
}
