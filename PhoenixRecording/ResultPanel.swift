import AppKit
import AVKit
import SwiftUI

@MainActor
final class ResultPanelController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(_ capture: Capture) {
        panel?.close()

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
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(12))
            if !Task.isCancelled { close() }
        }
    }

    func close() {
        dismissTask?.cancel()
        panel?.close()
        panel = nil
    }
}

struct ResultView: View {
    let capture: Capture
    let onClose: () -> Void

    @State private var status: String?
    @State private var isUploading = false
    @State private var sharedURL: URL?

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
            }
        }
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
            VideoPlayer(player: AVPlayer(url: capture.fileURL))
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
                let url = try await Preferences.shared.makeUploader().upload(capture)
                sharedURL = url
                Clipboard.copyText(url.absoluteString)
                status = "Link copied: \(url.absoluteString)"
            } catch {
                status = error.localizedDescription
            }
        }
    }
}
