import Foundation
import Metal
import MetalKit
import QuartzCore

/// Helium-inspired hall: brick arcade, chroma torches, CRT meters. Metal fragment scene.
final class HallOfTorchesScene: VisualizerScene, MetalRenderable {
    static let id = "hall-of-torches"
    static let displayName = "Hall of Torches"
    static let renderer: SceneRendererKind = .metal

    private var device: MTLDevice?
    private var pipeline: MTLRenderPipelineState?
    private var uniformBuffer: MTLBuffer?
    private var commandQueue: MTLCommandQueue?
    private var startTime = CACurrentMediaTime()
    private weak var attachedView: MTKView?

    func attach(to target: SceneHostTarget) {
        guard case .metal(let view) = target else { return }
        attachedView = view
        guard let device = view.device ?? MTLCreateSystemDefaultDevice() else { return }
        if self.device?.registryID != device.registryID {
            self.device = device
            pipeline = nil
        }
        if pipeline == nil {
            buildPipeline(device: device, colorFormat: view.colorPixelFormat)
        }
        if uniformBuffer == nil {
            uniformBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * 256, options: .storageModeShared)
        }
        if commandQueue == nil {
            commandQueue = device.makeCommandQueue()
        }
        view.device = device
    }

    func detach() {
        attachedView?.delegate = nil
        attachedView = nil
    }

    func handle(_ event: SceneEvent) {
        if case .randomize = event {
            startTime = CACurrentMediaTime()
        }
    }

    func update(features: AudioFeatures, dt: TimeInterval, preset: VisualizerPreset) {
        _ = features
        _ = dt
        _ = preset
    }

    func render(in view: MTKView, features: AudioFeatures, preset: VisualizerPreset) {
        attach(to: .metal(view))
        guard
            let pipeline,
            let uniformBuffer,
            let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        fillUniforms(features: features, preset: preset, size: view.drawableSize)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func buildPipeline(device: MTLDevice, colorFormat: MTLPixelFormat) {
        guard let library = device.makeDefaultLibrary() else { return }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "hall_vertex")
        desc.fragmentFunction = library.makeFunction(name: "hall_fragment")
        desc.colorAttachments[0].pixelFormat = colorFormat
        pipeline = try? device.makeRenderPipelineState(descriptor: desc)
    }

    private func fillUniforms(features: AudioFeatures, preset: VisualizerPreset, size: CGSize) {
        guard let ptr = uniformBuffer?.contents().bindMemory(to: Float.self, capacity: 256) else { return }
        let time = Float(CACurrentMediaTime() - startTime)
        ptr[0] = time
        ptr[1] = features.bass
        ptr[2] = features.mid
        ptr[3] = features.treble
        ptr[4] = features.rms
        ptr[5] = features.peak
        ptr[6] = features.onset
        ptr[7] = features.isSilent ? 1 : 0
        ptr[8] = features.gain
        ptr[9] = Float(min(features.bands.count, 64))
        ptr[10] = Float(size.width)
        ptr[11] = Float(size.height)

        let chroma = DSPConfig.resample(features.chroma, to: 12)
        for i in 0..<12 { ptr[12 + i] = chroma[i] }

        let bands = DSPConfig.resample(features.bands, to: 64)
        for i in 0..<64 { ptr[24 + i] = bands[i] }

        let wave = DSPConfig.resample(features.waveform, to: 128)
        for i in 0..<128 { ptr[88 + i] = wave[i] }

        _ = preset
    }
}
