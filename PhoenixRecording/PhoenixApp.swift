import SwiftUI

@main
struct PhoenixApp: App {
    @StateObject private var controller = CaptureController()
    @StateObject private var updater = Updater()

    var body: some Scene {
        Window("Ember", id: "main") {
            MainView(controller: controller, updater: updater)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 720)

        MenuBarExtra {
            MenuContent(controller: controller, updater: updater)
        } label: {
            if controller.isRecording {
                Image(systemName: "record.circle.fill")
            } else {
                Image("MenuBarIcon")
                    .opacity(controller.isBuffering ? 1 : 0.55)
            }
        }
    }

}

struct MenuContent: View {
    @ObservedObject var controller: CaptureController
    @ObservedObject var updater: Updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Ember") { showMainWindow(.dashboard) }
        if controller.needsScreenPermission {
            Button("Allow Screen Recording...") {
                showMainWindow(.dashboard)
                controller.requestScreenPermission()
            }
        }
        Divider()

        if let release = updater.available {
            Button(updater.isInstalling ? "Updating..." : "Install Update (build \(release.build))") {
                Task {
                    do { try await updater.install() } catch { controller.present(error) }
                }
            }
            .disabled(updater.isInstalling)
            Divider()
        }

        if controller.isBuffering {
            Button("Save Clip (\u{2325}\u{21E7}C)") { controller.saveClip() }
                .disabled(controller.isSavingClip)
            Button("Turn Off Replay Buffer") { controller.stopBuffer() }
        } else {
            Button("Turn On Replay Buffer") { controller.startBuffer() }
        }
        Toggle("Record Microphone", isOn: $controller.recordsMicrophone)

        Divider()

        Button("Capture Area (\u{2325}\u{21E7}4)") { controller.takeScreenshot(.area) }
        Button("Capture Window") { controller.takeScreenshot(.window) }
        Button("Capture Full Screen") { controller.takeScreenshot(.fullScreen) }

        Divider()

        if controller.isRecording {
            Button("Stop Recording") { controller.stopRecording() }
        } else {
            Button("Record Screen or Window...") { controller.startRecording() }
        }

        Divider()

        if let last = controller.lastCapture {
            Button("Show Last Capture") { controller.showResult(for: last) }
        }
        Button("Open Captures Folder") { NSWorkspace.shared.open(Preferences.shared.saveFolder) }

        Button("Settings...") { showMainWindow(.settings) }
            .keyboardShortcut(",")
        Button("Check for Updates (build \(updater.currentBuild))") {
            Task { await updater.check() }
        }
        Button("Quit Ember") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showMainWindow(_ section: MainSection) {
        controller.section = section
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
