import AppKit
import SwiftUI

@MainActor
final class ResultPanelController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private let slideDistance: CGFloat = 40

    private var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func show(_ capture: Capture) {
        if let old = panel {
            panel = nil
            dismiss(old, duration: 0.15)
        }

        let view = ResultView(capture: capture) { [weak self] in self?.close() }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 260),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: view)

        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 340, y: screen.minY + 20))
        }
        let resting = panel.frame
        if !reducesMotion {
            panel.setFrameOrigin(NSPoint(x: resting.minX + slideDistance, y: resting.minY))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(resting, display: true)
            panel.animator().alphaValue = 1
        }

        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(12))
            if !Task.isCancelled { close() }
        }
    }

    func close() {
        dismissTask?.cancel()
        guard let panel else { return }
        self.panel = nil
        dismiss(panel, duration: 0.22)
    }

    private func dismiss(_ panel: NSPanel, duration: TimeInterval) {
        var target = panel.frame
        if !reducesMotion {
            target.origin.x += slideDistance
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.close()
        }
    }
}

struct ResultView: View {
    let capture: Capture
    let onClose: () -> Void

    @State private var status: String?
    @State private var isUploading = false
    @State private var sharedURL: URL?
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 12) {
            preview
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onDrag { NSItemProvider(contentsOf: capture.fileURL) ?? NSItemProvider() }

            HStack {
                Button("Copy") {
                    Clipboard.copyFile(capture)
                    status = capture.kind.isVideo ? "Video copied" : "Image copied"
                }
                .keyboardShortcut("c")

                Button(isUploading ? "Preparing..." : "Copy Link") { share() }
                    .disabled(isUploading)

                Spacer()

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([capture.fileURL])
                } label: {
                    Image(systemName: "folder")
                }
                .help("Show in Finder")
            }

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: status)
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder
    private var preview: some View {
        switch capture.kind {
        case .screenshot:
            if let image = NSImage(contentsOf: capture.fileURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        case .clip, .recording:
            // A thumbnail rather than SwiftUI's VideoPlayer, which crashes on
            // macOS 26 when the app is built with the macOS 15 SDK.
            ZStack {
                Rectangle().fill(.black)
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                Image(systemName: "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .contentShape(Rectangle())
            .onTapGesture { NSWorkspace.shared.open(capture.fileURL) }
            .task(id: capture.fileURL) {
                thumbnail = await Library.thumbnail(for: capture, size: CGSize(width: 320, height: 180))
            }
        }
    }

    private func share() {
        if let sharedURL {
            Clipboard.copyText(sharedURL.absoluteString)
            status = "Link copied"
            return
        }

        isUploading = true
        status = nil
        Task {
            defer { isUploading = false }
            do {
                let url = try await Library.share(capture)
                sharedURL = url
                Clipboard.copyText(url.absoluteString)
                status = "Link copied: \(url.absoluteString)"
            } catch {
                status = error.localizedDescription
            }
        }
    }
}
