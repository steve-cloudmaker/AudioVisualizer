import Foundation

struct SceneRegistry {
    let all: [SceneMetadata]

    static let `default` = SceneRegistry(all: [
        SceneMetadata(id: AnalyzerStripScene.id, displayName: AnalyzerStripScene.displayName, renderer: .canvas, isQueuedPack: false),
        SceneMetadata(id: HallOfTorchesScene.id, displayName: HallOfTorchesScene.displayName, renderer: .metal, isQueuedPack: false),
        SceneMetadata(id: PlinkoScene.id, displayName: PlinkoScene.displayName, renderer: .spriteKit, isQueuedPack: false),
        SceneMetadata(id: ClawScene.id, displayName: ClawScene.displayName, renderer: .spriteKit, isQueuedPack: false),
        SceneMetadata(id: MicrographicScene.id, displayName: MicrographicScene.displayName, renderer: .canvas, isQueuedPack: false)
    ])

    func metadata(for id: String) -> SceneMetadata {
        all.first { $0.id == id } ?? all[0]
    }

    var v1IDs: [String] {
        all.filter { !$0.isQueuedPack }.map(\.id)
    }
}
