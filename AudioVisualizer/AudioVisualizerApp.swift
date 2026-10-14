import SwiftUI

@main
struct AudioVisualizerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HostView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 720)
        #endif
    }
}
