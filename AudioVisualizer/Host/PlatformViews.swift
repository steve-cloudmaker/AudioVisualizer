import MetalKit
import SpriteKit
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

protocol MetalRenderable: AnyObject {
    func render(in view: MTKView, features: AudioFeatures, preset: VisualizerPreset)
}

struct MetalStage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        MetalViewRepresentable(model: model)
            .ignoresSafeArea()
    }
}

private struct MetalViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> MetalDrawCoordinator {
        MetalDrawCoordinator(model: model)
    }
}

final class MetalDrawCoordinator: NSObject, MTKViewDelegate {
    let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let tick = MainActor.assumeIsolated {
            model.tickFrame()
        }
        if let metalScene = tick.scene as? MetalRenderable {
            metalScene.render(in: view, features: tick.features, preset: tick.preset)
        }
    }
}

#if os(macOS)
extension MetalViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView {
        let view = makeMetalView()
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        view.delegate = context.coordinator
        MainActor.assumeIsolated {
            model.currentScene.attach(to: .metal(view))
        }
    }
}
#else
extension MetalViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let view = makeMetalView()
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        view.delegate = context.coordinator
        MainActor.assumeIsolated {
            model.currentScene.attach(to: .metal(view))
        }
    }
}
#endif

private func makeMetalView() -> MTKView {
    let view = MTKView()
    view.device = MTLCreateSystemDefaultDevice()
    view.colorPixelFormat = .bgra8Unorm
    view.clearColor = MTLClearColor(red: 0.02, green: 0.01, blue: 0.01, alpha: 1)
    view.isPaused = false
    view.enableSetNeedsDisplay = false
    view.preferredFramesPerSecond = 120
    view.framebufferOnly = true
    view.autoResizeDrawable = true
    return view
}

struct SpriteKitStage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SpriteViewRepresentable(model: model)
            .ignoresSafeArea()
    }
}

private struct SpriteViewRepresentable {
    let model: AppModel
}

#if os(macOS)
extension SpriteViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> SKView {
        makeSKView()
    }

    func updateNSView(_ view: SKView, context: Context) {
        MainActor.assumeIsolated {
            bind(view)
        }
    }
}
#else
extension SpriteViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> SKView {
        makeSKView()
    }

    func updateUIView(_ view: SKView, context: Context) {
        MainActor.assumeIsolated {
            bind(view)
        }
    }
}
#endif

private extension SpriteViewRepresentable {
    @MainActor
    func bind(_ view: SKView) {
        model.currentScene.attach(to: .spriteKit(view))
        if let pumped = model.currentScene as? any SpritePumpedScene {
            pumped.setFramePump { [weak model] in
                guard let model else { return }
                MainActor.assumeIsolated {
                    _ = model.tickFrame()
                }
            }
        }
    }
}

private func makeSKView() -> SKView {
    let view = SKView()
    view.ignoresSiblingOrder = true
    view.preferredFramesPerSecond = 120
    return view
}

struct CanvasStage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TimelineView(.animation) { _ in
            let tick = model.tickFrame()
            Canvas { context, size in
                if let drawable = tick.scene as? any CanvasDrawableScene {
                    drawable.draw(context, size: size, features: tick.features, preset: tick.preset)
                }
            }
        }
        .onAppear {
            model.currentScene.attach(to: .canvas)
        }
        .ignoresSafeArea()
    }
}

struct SceneStageView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let kind = model.registry.metadata(for: model.selectedSceneID).renderer
        switch kind {
        case .canvas:
            CanvasStage()
        case .metal:
            MetalStage()
        case .spriteKit:
            SpriteKitStage()
        }
    }
}
