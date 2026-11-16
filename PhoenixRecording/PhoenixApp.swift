import SwiftUI

@main
struct PhoenixApp: App {
    @StateObject private var controller = CaptureController()
    @StateObject private var updater = Updater()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller, updater: updater)
        } label: {
            Image(systemName: menuBarSymbol)
        }
    }

    private var menuBarSymbol: String {
        if controller.isRecording { return "record.circle.fill" }
        return controller.isBuffering ? "dot.circle.viewfinder" : "camera.viewfinder"
    }
}

struct MenuContent: View {
    @ObservedObject var controller: CaptureController
    @ObservedObject var updater: Updater

    var body: some View {
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

        Button("Settings...") { controller.showSettings() }
            .keyboardShortcut(",")
        Button("Check for Updates (build \(updater.currentBuild))") {
            Task { await updater.check() }
        }
        Button("Quit Phoenix") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
