import AppKit
import SwiftUI

// SwiftUI's Settings scene doesn't reliably open from a menu bar-only app,
// because the app is never active when the menu item is clicked.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(controller: CaptureController) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(controller: controller))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Phoenix Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
