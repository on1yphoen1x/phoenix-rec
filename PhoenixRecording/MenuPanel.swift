import AppKit
import SwiftUI

struct MenuPanel: View {
    @ObservedObject var controller: CaptureController
    @ObservedObject var updater: Updater
    @AppStorage("theme") private var themeID = Theme.all[0].id
    @Environment(\.openWindow) private var openWindow

    private var theme: Theme { Theme.named(themeID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            clipButton

            if controller.isBuffering {
                Button {
                    controller.saveClip()
                } label: {
                    HStack {
                        Label(controller.isSavingClip ? "Saving..." : "Save Clip", systemImage: "square.and.arrow.down")
                        Spacer()
                        KeyCaps(keys: ["\u{2325}", "\u{21E7}", "C"])
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(controller.isSavingClip)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider().overlay(theme.border)

            VStack(spacing: 8) {
                if controller.needsScreenPermission {
                    PanelRow(symbol: "lock.shield", title: "Allow Screen Recording", subtitle: "Flint can't record until you allow it") {
                        showMainWindow(.dashboard)
                        controller.requestScreenPermission()
                    }
                }
                if let release = updater.available {
                    PanelRow(symbol: "arrow.down.circle", title: updater.isInstalling ? "Updating..." : "Install Update",
                             subtitle: "Build \(release.build) is ready") {
                        Task {
                            do { try await updater.install() } catch { controller.present(error) }
                        }
                    }
                    .disabled(updater.isInstalling)
                }
                PanelRow(symbol: "macwindow", title: "Open Flint", subtitle: "Show the main window") {
                    showMainWindow(.dashboard)
                }
                PanelRow(symbol: "camera.viewfinder", title: "Take Screenshot", subtitle: "Drag over an area, or \u{2325}\u{21E7}4") {
                    closePanel()
                    controller.takeScreenshot(.area)
                }
                if controller.isRecording {
                    PanelRow(symbol: "stop.circle", title: "Stop Recording", subtitle: "Save the recording so far") {
                        controller.stopRecording()
                    }
                } else {
                    PanelRow(symbol: "rectangle.dashed.badge.record", title: "Record Screen or Window", subtitle: "A full recording, not a clip") {
                        closePanel()
                        controller.startRecording()
                    }
                }
                if let last = controller.lastCapture {
                    PanelRow(symbol: "photo.on.rectangle", title: "Show Last Capture", subtitle: last.fileURL.lastPathComponent) {
                        closePanel()
                        controller.showResult(for: last)
                    }
                }
            }

            footer
        }
        .padding(20)
        .frame(width: 340)
        .background(theme.background)
        .environment(\.theme, theme)
        .tint(theme.accent)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .animation(.easeOut(duration: 0.2), value: controller.isBuffering)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Flint")
                    .font(.system(size: 16, weight: .semibold))
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
        }
    }

    private var clipButton: some View {
        Button {
            controller.isBuffering ? controller.stopBuffer() : controller.startBuffer()
        } label: {
            Label(controller.isBuffering ? "Stop Clipping" : (controller.isStartingBuffer ? "Starting..." : "Start Clipping"),
                  systemImage: controller.isBuffering ? "stop.fill" : "record.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(controller.isBuffering ? AnyShapeStyle(Color.red.opacity(0.85)) : AnyShapeStyle(theme.accent.gradient))
                }
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .disabled(controller.isStartingBuffer)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Flint", systemImage: "power")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Spacer()

            footerIcon("arrow.triangle.2.circlepath", help: "Check for updates (build \(updater.currentBuild))") {
                Task { _ = await updater.check() }
            }
            footerIcon("folder", help: "Open the captures folder") {
                closePanel()
                NSWorkspace.shared.open(Preferences.shared.saveFolder)
            }
            footerIcon("gearshape", help: "Settings") {
                showMainWindow(.settings)
            }
        }
    }

    private var status: String {
        if controller.isRecording { return "Recording" }
        if controller.isBuffering { return "Clipping \(controller.captureLabel)" }
        if controller.needsScreenPermission { return "Needs Screen Recording permission" }
        return "Ready to clip"
    }

    private func footerIcon(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 32, height: 30)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func showMainWindow(_ section: MainSection) {
        closePanel()
        controller.section = section
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }

    // The window-style menu bar panel stays open after a click, so actions that
    // move somewhere else close it by hand.
    private func closePanel() {
        NSApp.keyWindow?.close()
    }
}

struct PanelRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .truncationMode(.middle)
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isHovering ? theme.accent.opacity(0.1) : theme.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(theme.border))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
