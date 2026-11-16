import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case clips = "Clips"
    case screenshots = "Screenshots"
    case shared = "Shared"
    case settings = "Settings"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dashboard: "chart.line.uptrend.xyaxis"
        case .clips: "play.rectangle.on.rectangle"
        case .screenshots: "camera.viewfinder"
        case .shared: "icloud.and.arrow.up"
        case .settings: "gearshape"
        }
    }
}

struct MainView: View {
    @ObservedObject var controller: CaptureController
    @ObservedObject var updater: Updater

    var body: some View {
        NavigationSplitView {
            List(selection: $controller.section) {
                Section {
                    ForEach([MainSection.dashboard, .clips, .screenshots, .shared]) { section in
                        Label(section.rawValue, systemImage: section.symbol).tag(section)
                    }
                }
                Section {
                    Label(MainSection.settings.rawValue, systemImage: MainSection.settings.symbol)
                        .tag(MainSection.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .safeAreaInset(edge: .bottom) {
                SidebarFooter(controller: controller, updater: updater)
            }
        } detail: {
            detail
                .navigationTitle(controller.section.rawValue)
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear { controller.reloadLibrary() }
    }

    @ViewBuilder
    private var detail: some View {
        switch controller.section {
        case .dashboard:
            DashboardView(controller: controller)
        case .clips:
            CaptureGrid(controller: controller, captures: controller.captures.filter { $0.kind.isVideo },
                        emptyTitle: "No clips yet",
                        emptyMessage: "Turn on the replay buffer, then press Option-Shift-C to save the last few seconds.")
        case .screenshots:
            CaptureGrid(controller: controller, captures: controller.captures.filter { !$0.kind.isVideo },
                        emptyTitle: "No screenshots yet",
                        emptyMessage: "Press Option-Shift-4 and drag over the part of the screen you want.")
        case .shared:
            CaptureGrid(controller: controller, captures: controller.captures.filter { Library.shareLink(for: $0) != nil },
                        emptyTitle: "Nothing shared yet",
                        emptyMessage: "Captures appear here after you press Copy Link on them.")
        case .settings:
            ScrollView {
                SettingsView(controller: controller)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct SidebarFooter: View {
    @ObservedObject var controller: CaptureController
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(controller.isBuffering ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(controller.isBuffering ? "Replay buffer on" : "Replay buffer off")
                    .font(.callout)
            }

            if let release = updater.available {
                Button(updater.isInstalling ? "Updating..." : "Install build \(release.build)") {
                    Task {
                        do { try await updater.install() } catch { controller.present(error) }
                    }
                }
                .disabled(updater.isInstalling)
            } else {
                Button("Check for Updates") {
                    Task { await updater.check() }
                }
                .buttonStyle(.link)
            }

            Text("Build \(updater.currentBuild)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

struct DashboardView: View {
    @ObservedObject var controller: CaptureController

    private var clips: [Capture] { controller.captures.filter { $0.kind.isVideo } }
    private var screenshots: [Capture] { controller.captures.filter { !$0.kind.isVideo } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    if controller.isBuffering {
                        Button("Save Clip") { controller.saveClip() }
                            .buttonStyle(.borderedProminent)
                            .disabled(controller.isSavingClip)
                        Button("Turn Off Replay Buffer") { controller.stopBuffer() }
                    } else {
                        Button("Turn On Replay Buffer") { controller.startBuffer() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Take Screenshot") { controller.takeScreenshot(.area) }
                    Spacer()
                    Button("Open Folder") { NSWorkspace.shared.open(Preferences.shared.saveFolder) }
                }
                .controlSize(.large)

                HStack(spacing: 12) {
                    StatTile(title: "Clips", value: "\(clips.count)")
                    StatTile(title: "Screenshots", value: "\(screenshots.count)")
                    StatTile(title: "On disk", value: diskUsage)
                    StatTile(title: "Shared", value: "\(controller.captures.filter { Library.shareLink(for: $0) != nil }.count)")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent")
                        .font(.title3.weight(.semibold))
                    if controller.captures.isEmpty {
                        Text("Your clips and screenshots show up here. Press Option-Shift-C to save a clip or Option-Shift-4 for a screenshot.")
                            .foregroundStyle(.secondary)
                    } else {
                        CaptureCards(controller: controller, captures: Array(controller.captures.prefix(8)))
                    }
                }
            }
            .padding(24)
        }
    }

    private var diskUsage: String {
        let bytes = controller.captures.reduce(0) { $0 + Library.size(of: $1) }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct CaptureGrid: View {
    @ObservedObject var controller: CaptureController
    let captures: [Capture]
    let emptyTitle: String
    let emptyMessage: String

    var body: some View {
        if captures.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: "tray", description: Text(emptyMessage))
        } else {
            ScrollView {
                CaptureCards(controller: controller, captures: captures)
                    .padding(24)
            }
        }
    }
}

struct CaptureCards: View {
    @ObservedObject var controller: CaptureController
    let captures: [Capture]

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(captures, id: \.fileURL) { capture in
                CaptureCard(controller: controller, capture: capture)
            }
        }
    }
}

struct CaptureCard: View {
    @ObservedObject var controller: CaptureController
    let capture: Capture

    @State private var thumbnail: NSImage?
    @State private var status: String?
    @State private var isUploading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Rectangle().fill(.black)
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                if capture.kind.isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture(count: 2) { NSWorkspace.shared.open(capture.fileURL) }
            .onDrag { NSItemProvider(contentsOf: capture.fileURL) ?? NSItemProvider() }

            Text(capture.fileURL.deletingPathExtension().lastPathComponent)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(status ?? detailLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack {
                Button("Copy") {
                    Clipboard.copyFile(capture)
                    flash(capture.kind.isVideo ? "Video copied" : "Image copied")
                }
                Button(isUploading ? "Preparing..." : "Copy Link") { share() }
                    .disabled(isUploading)
                Spacer()
                Menu {
                    Button("Open") { NSWorkspace.shared.open(capture.fileURL) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([capture.fileURL]) }
                    Divider()
                    Button("Move to Bin", role: .destructive) { controller.trash(capture) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .task(id: capture.fileURL) {
            thumbnail = await Library.thumbnail(for: capture, size: CGSize(width: 320, height: 180))
        }
    }

    private var detailLine: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(Library.size(of: capture)), countStyle: .file)
        let date = capture.createdAt.formatted(date: .abbreviated, time: .shortened)
        let shared = Library.shareLink(for: capture) == nil ? "" : " \u{00B7} Shared"
        return "\(date) \u{00B7} \(size)\(shared)"
    }

    private func share() {
        isUploading = true
        Task {
            defer { isUploading = false }
            do {
                let url = try await Library.share(capture)
                Clipboard.copyText(url.absoluteString)
                flash("Link copied")
                controller.reloadLibrary()
            } catch {
                flash(error.localizedDescription)
            }
        }
    }

    private func flash(_ message: String) {
        status = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if status == message { status = nil }
        }
    }
}
