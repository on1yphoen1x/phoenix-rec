import SwiftUI

@main
struct PhoenixApp: App {
    @StateObject private var controller = CaptureController()
    @StateObject private var updater = Updater()

    var body: some Scene {
        Window("Flint", id: "main") {
            MainView(controller: controller, updater: updater)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1120, height: 720)

        MenuBarExtra {
            MenuPanel(controller: controller, updater: updater)
        } label: {
            if controller.isRecording {
                Image(systemName: "record.circle.fill")
            } else {
                Image("MenuBarIcon")
                    .opacity(controller.isBuffering ? 1 : 0.55)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
