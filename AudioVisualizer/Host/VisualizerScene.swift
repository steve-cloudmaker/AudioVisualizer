import Foundation
import MetalKit
import SpriteKit
import SwiftUI

enum SceneRendererKind: String, Codable, CaseIterable {
    case metal
    case spriteKit
    case canvas
}

enum SceneEvent {
    case tap(CGPoint)
    case randomize
    case shake
}

enum SceneHostTarget {
    case metal(MTKView)
    case spriteKit(SKView)
    case canvas
}

/// Winamp-style plugin contract. One analysis pipeline, many scenes. Never a second FFT.
protocol VisualizerScene: AnyObject {
    static var id: String { get }
    static var displayName: String { get }
    static var renderer: SceneRendererKind { get }
    static var isQueuedPack: Bool { get }

    func attach(to target: SceneHostTarget)
    func update(features: AudioFeatures, dt: TimeInterval, preset: VisualizerPreset)
    func handle(_ event: SceneEvent)
    func detach()
}

extension VisualizerScene {
    static var isQueuedPack: Bool { false }
}

protocol CanvasDrawableScene: VisualizerScene {
    func draw(_ context: GraphicsContext, size: CGSize, features: AudioFeatures, preset: VisualizerPreset)
}

protocol SpritePumpedScene: VisualizerScene {
    func setFramePump(_ pump: (() -> Void)?)
}

struct SceneMetadata: Identifiable, Equatable {
    var id: String
    var displayName: String
    var renderer: SceneRendererKind
    var isQueuedPack: Bool
}

final class SceneFactory {
    static func make(_ id: String) -> any VisualizerScene {
        switch id {
        case AnalyzerStripScene.id:
            return AnalyzerStripScene()
        case HallOfTorchesScene.id:
            return HallOfTorchesScene()
        case PlinkoScene.id:
            return PlinkoScene()
        case ClawScene.id:
            return ClawScene()
        case MicrographicScene.id:
            return MicrographicScene()
        default:
            return AnalyzerStripScene()
        }
    }
}
