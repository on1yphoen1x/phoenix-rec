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

    var subtitle: String {
        switch self {
        case .dashboard: "Your replay buffer and latest captures"
        case .clips: "Every clip saved on this Mac"
        case .screenshots: "Screenshots saved on this Mac"
        case .shared: "Captures you've uploaded with Copy Link"
        case .settings: "Clipping, audio, sharing and how Ember looks"
        }
    }
}

struct MainView: View {
    @ObservedObject var controller: CaptureController
    @ObservedObject var updater: Updater
    @AppStorage("theme") private var themeID = Theme.all[0].id
    @State private var settingsTab = SettingsTab.clipping

    private var theme: Theme { Theme.named(themeID) }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(controller: controller, updater: updater)
                .frame(width: 230)

            VStack(alignment: .leading, spacing: 0) {
                header
                if controller.needsScreenPermission {
                    PermissionBanner(controller: controller)
                }
                Divider().overlay(theme.border)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(theme.background)
        }
        .ignoresSafeArea()
        .environment(\.theme, theme)
        .tint(theme.accent)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .frame(minWidth: 900, minHeight: 580)
        .onAppear { controller.reloadLibrary() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(controller.section.rawValue)
                    .font(.system(size: 22, weight: .semibold))
                    .lineLimit(1)
                Text(controller.section == .settings ? settingsTab.subtitle : controller.section.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(0)
            Spacer(minLength: 12)
            if controller.section == .settings {
                SettingsTabBar(selection: $settingsTab)
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)
        .padding(.bottom, 18)
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
            SettingsView(controller: controller, tab: settingsTab, themeID: $themeID)
        }
    }
}

struct PermissionBanner: View {
    @ObservedObject var controller: CaptureController
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 38, height: 38)
                .background(theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text("Ember needs Screen Recording permission")
                    .font(.callout.weight(.semibold))
                Text("Turn on Ember in System Settings, then reopen it. You only need to do this once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Open System Settings") { controller.requestScreenPermission() }
                .fixedSize()
            Button("Quit & Reopen") { controller.relaunch() }
                .buttonStyle(.borderedProminent)
                .fixedSize()
        }
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.accent.opacity(0.5)))
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }
}

struct Sidebar: View {
    @ObservedObject var controller: CaptureController
    @ObservedObject var updater: Updater
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 34, height: 34)
                Text("Ember")
                    .font(.system(size: 19, weight: .semibold))
            }
            .padding(.horizontal, 18)
            .padding(.top, 52)
            .padding(.bottom, 18)

            Divider().overlay(theme.border).padding(.horizontal, 18)

            VStack(spacing: 4) {
                ForEach([MainSection.dashboard, .clips, .screenshots, .shared]) { section in
                    SidebarItem(section: section, selection: $controller.section)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)

            Divider().overlay(theme.border).padding(.horizontal, 18).padding(.vertical, 12)

            SidebarItem(section: .settings, selection: $controller.section)
                .padding(.horizontal, 10)

            Spacer(minLength: 0)

            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            ZStack(alignment: .bottom) {
                theme.sidebarGradient
                SidebarScenery(theme: theme)
                    .frame(height: 260)
                    .opacity(0.9)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(theme.border).frame(width: 1)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(controller.isBuffering ? Color.green : Color.secondary.opacity(0.6))
                    .frame(width: 8, height: 8)
                Text(controller.isBuffering ? "Replay buffer on" : "Replay buffer off")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { controller.isBuffering },
                    set: { $0 ? controller.startBuffer() : controller.stopBuffer() }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            HStack {
                Text("Build \(updater.currentBuild)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if let release = updater.available {
                    Button(updater.isInstalling ? "Updating..." : "Install build \(release.build)") {
                        Task {
                            do { try await updater.install() } catch { controller.present(error) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(updater.isInstalling)
                } else {
                    Button("Check for Updates") {
                        Task { await updater.check() }
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.accent)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border))
        .padding(12)
    }
}

struct SidebarItem: View {
    let section: MainSection
    @Binding var selection: MainSection
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    private var isSelected: Bool { selection == section }

    var body: some View {
        Button {
            selection = section
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.secondary))
                Text(section.rawValue)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: 3, height: 16)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? theme.accent.opacity(0.18) : (isHovering ? Color.primary.opacity(0.06) : .clear))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct DashboardView: View {
    @ObservedObject var controller: CaptureController
    @Environment(\.theme) private var theme

    private var clips: [Capture] { controller.captures.filter { $0.kind.isVideo } }
    private var screenshots: [Capture] { controller.captures.filter { !$0.kind.isVideo } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    if controller.isBuffering {
                        Button { controller.saveClip() } label: {
                            Label("Save Clip", systemImage: "record.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.isSavingClip)
                    } else {
                        Button { controller.startBuffer() } label: {
                            Label("Turn On Replay Buffer", systemImage: "dot.circle.viewfinder")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button { controller.takeScreenshot(.area) } label: {
                        Label("Take Screenshot", systemImage: "camera.viewfinder")
                    }
                    Spacer()
                    Button { NSWorkspace.shared.open(Preferences.shared.saveFolder) } label: {
                        Label("Open Folder", systemImage: "folder")
                    }
                }
                .controlSize(.large)

                HStack(spacing: 14) {
                    StatTile(title: "Clips", value: "\(clips.count)", symbol: "play.rectangle")
                    StatTile(title: "Screenshots", value: "\(screenshots.count)", symbol: "photo")
                    StatTile(title: "On disk", value: diskUsage, symbol: "internaldrive")
                    StatTile(title: "Shared", value: "\(controller.captures.filter { Library.shareLink(for: $0) != nil }.count)",
                             symbol: "link")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent")
                        .font(.title3.weight(.semibold))
                    if controller.captures.isEmpty {
                        Text("Your clips and screenshots show up here. Press Option-Shift-C to save a clip or Option-Shift-4 for a screenshot.")
                            .foregroundStyle(.secondary)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.border))
                    } else {
                        CaptureCards(controller: controller, captures: Array(controller.captures.prefix(8)))
                    }
                }
            }
            .padding(28)
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
    let symbol: String
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 34, height: 34)
                .background(theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.border))
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
                    .padding(28)
            }
        }
    }
}

struct CaptureCards: View {
    @ObservedObject var controller: CaptureController
    let captures: [Capture]

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 16)]

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
    @Environment(\.theme) private var theme

    @State private var thumbnail: NSImage?
    @State private var status: String?
    @State private var isUploading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.black)
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if capture.kind.isVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.45), in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if Library.shareLink(for: capture) != nil {
                    Label("Shared", systemImage: "link")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(theme.accent, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .onTapGesture(count: 2) { NSWorkspace.shared.open(capture.fileURL) }
            .onDrag { NSItemProvider(contentsOf: capture.fileURL) ?? NSItemProvider() }

            VStack(alignment: .leading, spacing: 3) {
                Text(capture.fileURL.deletingPathExtension().lastPathComponent)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(status ?? detailLine)
                    .font(.caption)
                    .foregroundStyle(status == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(theme.accent))
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Button("Copy") {
                    Clipboard.copyFile(capture)
                    flash(capture.kind.isVideo ? "Video copied" : "Image copied")
                }
                .fixedSize()
                Button(isUploading ? "Preparing..." : "Copy Link") { share() }
                    .disabled(isUploading)
                    .fixedSize()
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
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.border))
        .task(id: capture.fileURL) {
            thumbnail = await Library.thumbnail(for: capture, size: CGSize(width: 320, height: 180))
        }
    }

    private var detailLine: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(Library.size(of: capture)), countStyle: .file)
        let date = capture.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "\(date) \u{00B7} \(size)"
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
