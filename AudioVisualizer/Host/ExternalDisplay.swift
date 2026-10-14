import SwiftUI

#if os(iOS)
import UIKit

/// Mirrors a read-only Analyzer Strip onto an external screen. Chrome stays on the iPad.
final class ExternalDisplayController: NSObject {
    private var window: UIWindow?
    private weak var model: AppModel?
    private var observers: [NSObjectProtocol] = []

    func start(model: AppModel) {
        self.model = model
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIScreen.didConnectNotification, object: nil, queue: .main) { [weak self] note in
            guard let screen = note.object as? UIScreen else { return }
            self?.attach(screen: screen)
        })
        observers.append(center.addObserver(forName: UIScreen.didDisconnectNotification, object: nil, queue: .main) { [weak self] _ in
            self?.detach()
        })
        if UIScreen.screens.count > 1 {
            attach(screen: UIScreen.screens[1])
        }
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        detach()
    }

    private func attach(screen: UIScreen) {
        MainActor.assumeIsolated {
            guard let model else { return }
            let window: UIWindow
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.screen == screen }) {
                window = UIWindow(windowScene: scene)
            } else {
                window = UIWindow(frame: screen.bounds)
            }
            let host = UIHostingController(rootView: ExternalMirrorView().environmentObject(model))
            host.view.backgroundColor = .black
            window.rootViewController = host
            window.isHidden = false
            self.window = window
            model.externalDisplayConnected = true
        }
    }

    private func detach() {
        MainActor.assumeIsolated {
            window?.isHidden = true
            window = nil
            model?.externalDisplayConnected = false
        }
    }
}
#endif

#if os(macOS)
import AppKit

final class ExternalDisplayController: NSObject {
    private var window: NSWindow?
    private weak var model: AppModel?

    func start(model: AppModel) {
        self.model = model
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        screensChanged()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        window?.close()
        window = nil
        MainActor.assumeIsolated {
            model?.externalDisplayConnected = false
        }
    }

    @objc private func screensChanged() {
        MainActor.assumeIsolated {
            guard let model else { return }
            if NSScreen.screens.count > 1, let screen = NSScreen.screens.last {
                if window == nil {
                    let window = NSWindow(
                        contentRect: screen.frame,
                        styleMask: [.borderless],
                        backing: .buffered,
                        defer: false,
                        screen: screen
                    )
                    window.setFrame(screen.frame, display: true)
                    window.level = .normal
                    window.isOpaque = true
                    window.backgroundColor = .black
                    window.contentView = NSHostingView(rootView: ExternalMirrorView().environmentObject(model))
                    window.makeKeyAndOrderFront(nil)
                    self.window = window
                } else {
                    window?.setFrame(screen.frame, display: true)
                }
                model.externalDisplayConnected = true
            } else {
                window?.close()
                window = nil
                model.externalDisplayConnected = false
            }
        }
    }
}
#endif

/// Second scene instance, same feature bus. Does not call `tickFrame` so the main stage stays the clock.
struct ExternalMirrorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var strip = AnalyzerStripScene()

    var body: some View {
        TimelineView(.animation) { _ in
            let features = model.bus.snapshot()
            Canvas { context, size in
                strip.update(features: features, dt: 1.0 / 60.0, preset: model.preset)
                strip.draw(context, size: size, features: features, preset: model.preset)
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
    }
}
