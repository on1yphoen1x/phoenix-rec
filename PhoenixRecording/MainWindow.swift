import AVFoundation
import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case clips = "Clips"
    case screenshots = "Screenshots"
    case recordings = "Recordings"
    case shared = "Shared"
    case settings = "Settings"

    var id: String { rawValue }

    static let tabs: [MainSection] = [.clips, .screenshots, .recordings, .shared]
}

struct MainView: View {
    @ObservedObject var controller: CaptureController
    @ObservedObject var updater: Updater
    @AppStorage("theme") private var themeID = Theme.all[0].id
    @State private var settingsTab = SettingsTab.clipping
    @State private var showsSetup = false

    private var theme: Theme { Theme.named(themeID) }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(controller: controller, openSetup: { showsSetup = true })
            if controller.needsScreenPermission {
                PermissionBanner(controller: controller)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            StatusBar(controller: controller, updater: updater)
        }
        .animation(.spring(duration: 0.35), value: controller.needsScreenPermission)
        .background(theme.background)
        .ignoresSafeArea()
        .environment(\.theme, theme)
        .tint(theme.accent)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .frame(minWidth: 900, minHeight: 580)
        .onAppear { controller.reloadLibrary() }
        .sheet(isPresented: $showsSetup) {
            ClippingSetupSheet(controller: controller)
                .environment(\.theme, theme)
                .tint(theme.accent)
                .preferredColorScheme(theme.isDark ? .dark : .light)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.section {
        case .clips:
            ClipsView(controller: controller, openSetup: { showsSetup = true })
        case .screenshots:
            CaptureGrid(controller: controller, captures: controller.captures.filter { $0.kind == .screenshot },
                        emptyTitle: "No screenshots yet",
                        emptyMessage: "Press Option-Shift-4 and drag over the part of the screen you want.")
        case .recordings:
            CaptureGrid(controller: controller, captures: controller.captures.filter { $0.kind == .recording },
                        emptyTitle: "No recordings yet",
                        emptyMessage: "Use Record Screen or Window in the menu bar for a full recording rather than a clip.")
        case .shared:
            CaptureGrid(controller: controller, captures: controller.captures.filter { Library.shareLink(for: $0) != nil },
                        emptyTitle: "Nothing shared yet",
                        emptyMessage: "Captures appear here after you press Copy Link on them.")
        case .settings:
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Settings")
                            .font(.system(size: 20, weight: .semibold))
                        Text(settingsTab.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    SettingsTabBar(selection: $settingsTab)
                        .layoutPriority(1)
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                SettingsView(controller: controller, tab: settingsTab, themeID: $themeID)
            }
        }
    }
}

struct TopBar: View {
    @ObservedObject var controller: CaptureController
    let openSetup: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            // Room for the window's close, minimise and zoom buttons.
            Color.clear.frame(width: 64, height: 1)

            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 24, height: 24)
                Text("FLINT")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(1.2)
            }
            .fixedSize()

            HStack(spacing: 2) {
                ForEach(MainSection.tabs) { section in
                    TopTab(title: section.rawValue, isSelected: controller.section == section) {
                        controller.section = section
                    }
                }
            }
            .padding(.leading, 6)

            Spacer(minLength: 12)

            BufferMeter(controller: controller)

            Button {
                controller.isBuffering ? controller.stopBuffer() : openSetup()
            } label: {
                Text(controller.isBuffering ? "Stop Clipping" : (controller.isStartingBuffer ? "Starting..." : "Start Clipping"))
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(ClipToggleStyle(isBuffering: controller.isBuffering))
            .disabled(controller.isStartingBuffer)

            Button {
                controller.section = controller.section == .settings ? .clips : .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(controller.section == .settings ? theme.accent : .secondary)
                    .frame(width: 32, height: 30)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(theme.sidebarTop)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.border).frame(height: 1)
        }
    }
}

struct TopTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? theme.surface : (isHovering ? Color.primary.opacity(0.05) : .clear))
                }
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct ClipToggleStyle: ButtonStyle {
    let isBuffering: Bool
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isBuffering ? Color.primary : theme.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isBuffering ? theme.surface : theme.accent)
                    .opacity(configuration.isPressed ? 0.8 : 1)
            }
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(isBuffering ? theme.border : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct BufferMeter: View {
    @ObservedObject var controller: CaptureController
    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = Preferences.shared.clipSeconds
            let filled = BufferMath.filledSeconds(since: controller.bufferStartedAt, now: context.date, total: total)
            HStack(spacing: 9) {
                Circle()
                    .fill(controller.isBuffering ? theme.accent : Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(controller.isBuffering ? "BUFFER" : "OFF")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(filled), total: Double(total))
                    .progressViewStyle(.linear)
                    .frame(width: 80)
                Text("\(BufferMath.clock(filled)) / \(BufferMath.clock(total))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border))
        }
        .help(controller.isBuffering ? "How much of the clip length is ready to save" : "Clipping is off")
    }
}

enum BufferMath {
    static func filledSeconds(since start: Date?, now: Date, total: Int) -> Int {
        guard let start else { return 0 }
        return min(total, max(0, Int(now.timeIntervalSince(start))))
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct StatusBar: View {
    @ObservedObject var controller: CaptureController
    @ObservedObject var updater: Updater
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 18) {
            Text("\(clipCount) clips \u{00B7} \(diskUsage) on disk")
            Text("\(sharedCount) shared")
            Spacer(minLength: 12)
            if let release = updater.available {
                Button(updater.isInstalling ? "Updating..." : "Install build \(release.build)") {
                    Task {
                        do { try await updater.install() } catch { controller.present(error) }
                    }
                }
                .buttonStyle(AccentButtonStyle())
                .controlSize(.small)
                .disabled(updater.isInstalling)
            } else {
                Button("Check for Updates") {
                    Task { _ = await updater.check() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
            }
            Text("Build \(updater.currentBuild)")
                .monospacedDigit()
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 18)
        .frame(height: 32)
        .background(theme.sidebarTop)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.border).frame(height: 1)
        }
    }

    private var clipCount: Int { controller.captures.filter { $0.kind == .clip }.count }
    private var sharedCount: Int { controller.captures.filter { Library.shareLink(for: $0) != nil }.count }

    private var diskUsage: String {
        let bytes = controller.captures.reduce(0) { $0 + Library.size(of: $1) }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
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
                .background(theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
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
                .buttonStyle(QuietButtonStyle())
                .fixedSize()
            Button("Quit & Reopen") { controller.relaunch() }
                .buttonStyle(AccentButtonStyle())
                .fixedSize()
        }
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.accent.opacity(0.5)))
        .padding(.horizontal, 26)
        .padding(.top, 16)
    }
}

struct ClipsView: View {
    @ObservedObject var controller: CaptureController
    let openSetup: () -> Void
    @Environment(\.theme) private var theme
    @State private var filter: String?
    @State private var search = ""

    private struct ClipGroup: Identifiable {
        let name: String
        let bundleID: String?
        let clips: [Capture]
        var id: String { name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LiveBufferCard(controller: controller, openSetup: openSetup)

                if allGroups.isEmpty {
                    emptyState
                } else {
                    filterBar
                    if visibleGroups.isEmpty {
                        Text("No clips match \"\(search)\".")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(visibleGroups) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(nsImage: group.bundleID.map { AppIconCache.icon(for: $0) } ?? NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: nil) ?? NSImage())
                                    .resizable()
                                    .frame(width: 22, height: 22)
                                Text(group.name)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(group.clips.count == 1 ? "1 clip" : "\(group.clips.count) clips")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            CaptureCards(controller: controller, captures: group.clips)
                        }
                    }
                }
            }
            .padding(26)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No clips yet")
                .font(.headline)
            Text("Start clipping, then press Option-Shift-C to save the last few seconds. Clips are grouped by the game they came from.")
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border))
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All games", isSelected: filter == nil) { filter = nil }
                    ForEach(allGroups) { group in
                        FilterChip(title: group.name, isSelected: filter == group.name) { filter = group.name }
                    }
                }
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search clips", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 220)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border))
        }
    }

    private var allGroups: [ClipGroup] {
        let clips = controller.captures.filter { $0.kind == .clip }
        var order: [String] = []
        var byName: [String: (String?, [Capture])] = [:]
        for clip in clips {
            let source = Library.source(for: clip)
            let name = source?.name ?? "Desktop"
            if byName[name] == nil {
                order.append(name)
                byName[name] = (source?.bundleID, [])
            }
            byName[name]?.1.append(clip)
        }
        return order.compactMap { name in
            byName[name].map { ClipGroup(name: name, bundleID: $0.0, clips: $0.1) }
        }
    }

    private var visibleGroups: [ClipGroup] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return allGroups
            .filter { filter == nil || $0.name == filter }
            .compactMap { group in
                guard !query.isEmpty else { return group }
                if group.name.localizedCaseInsensitiveContains(query) { return group }
                let matches = group.clips.filter { $0.fileURL.lastPathComponent.localizedCaseInsensitiveContains(query) }
                return matches.isEmpty ? nil : ClipGroup(name: group.name, bundleID: group.bundleID, clips: matches)
            }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.onAccent : Color.primary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(isSelected ? theme.accent : theme.surface))
                .overlay(Capsule().stroke(isSelected ? .clear : theme.border))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct LiveBufferCard: View {
    @ObservedObject var controller: CaptureController
    let openSetup: () -> Void
    @Environment(\.theme) private var theme

    private let cellCount = 10

    var body: some View {
        let total = Preferences.shared.clipSeconds
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Last \(total) seconds")
                    .font(.system(size: 17, weight: .semibold))
                    .fixedSize()
                Text(ClipSummary.line(controller: controller))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 12)
                if controller.isBuffering {
                    KeyCaps(keys: ["\u{2325}", "\u{21E7}", "C"])
                    Button(controller.isSavingClip ? "Saving..." : "Save Clip") { controller.saveClip() }
                        .buttonStyle(AccentButtonStyle())
                        .disabled(controller.isSavingClip)
                        .fixedSize()
                } else {
                    Button(controller.isStartingBuffer ? "Starting..." : "Start Clipping") { openSetup() }
                        .buttonStyle(AccentButtonStyle())
                        .disabled(controller.isStartingBuffer)
                        .fixedSize()
                }
                Button("Change Source") { openSetup() }
                    .buttonStyle(QuietButtonStyle())
                    .fixedSize()
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let filled = BufferMath.filledSeconds(since: controller.bufferStartedAt, now: context.date, total: total)
                let lit = total == 0 ? 0 : Int((Double(filled) / Double(total) * Double(cellCount)).rounded(.up))
                VStack(spacing: 7) {
                    HStack(spacing: 4) {
                        ForEach(0..<cellCount, id: \.self) { index in
                            let isLit = index >= cellCount - lit
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isLit ? AnyShapeStyle(theme.accent.opacity(0.3 + 0.07 * Double(index)))
                                            : AnyShapeStyle(theme.background))
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(theme.border))
                                .frame(height: 54)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(controller.isBuffering ? theme.accent : theme.border)
                            .frame(width: 2)
                            .padding(.vertical, -5)
                            .offset(x: 3)
                    }
                    .overlay {
                        if !controller.isBuffering {
                            Text("Clipping is off. Start it and this fills with the last \(total) seconds.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .animation(.easeOut(duration: 0.4), value: lit)

                    HStack {
                        ForEach(tickLabels(total: total), id: \.self) { label in
                            Text(label)
                            if label != "now" { Spacer(minLength: 0) }
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(18)
        .background {
            ZStack(alignment: .trailing) {
                theme.surface
                SidebarScenery(theme: theme)
                    .frame(width: 320)
                    .opacity(0.35)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(controller.isBuffering ? theme.accent.opacity(0.55) : theme.border))
        .animation(.easeOut(duration: 0.25), value: controller.isBuffering)
    }

    private func tickLabels(total: Int) -> [String] {
        let steps = 5
        return (0...steps).map { step in
            let seconds = total - total * step / steps
            return seconds == 0 ? "now" : "-\(BufferMath.clock(seconds))"
        }
    }
}

enum ClipSummary {
    @MainActor
    static func line(controller: CaptureController) -> String {
        let prefs = Preferences.shared
        let options = controller.captureOptions
        let target: String
        switch prefs.captureSource {
        case .screen:
            target = "Screen \u{00B7} " + (options.displays.first { $0.id == prefs.captureDisplayID }?.name ?? "Main display")
        case .window:
            target = options.windows.first { $0.id == prefs.captureWindowID }?.name ?? "A window"
        case .app:
            target = options.apps.first { $0.id == prefs.captureAppID }?.name ?? "An app"
        }
        let desktop: String
        switch prefs.audioSource {
        case .all: desktop = "All audio"
        case .app: desktop = (options.apps.first { $0.id == prefs.audioAppID }?.name ?? "One app") + " audio"
        case .off: desktop = "No desktop audio"
        }
        let audio = controller.recordsMicrophone ? "\(desktop) + mic" : desktop
        return [target, audio, "\(prefs.clipQuality.rawValue)60"].joined(separator: " \u{00B7} ")
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
                    .padding(26)
            }
        }
    }
}

struct CaptureCards: View {
    @ObservedObject var controller: CaptureController
    let captures: [Capture]

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
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
    @State private var duration: String?
    @State private var status: String?
    @State private var isUploading = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Rectangle().fill(.black)
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                if capture.kind.isVideo, isHovering {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.55), in: Circle())
                        .transition(.opacity)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                if Library.shareLink(for: capture) != nil {
                    Text("Shared")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(theme.onAccent)
                        .padding(8)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let duration {
                    Text(duration)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture(count: 2) { NSWorkspace.shared.open(capture.fileURL) }
            .onDrag { NSItemProvider(contentsOf: capture.fileURL) ?? NSItemProvider() }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(capture.fileURL.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Text(status ?? timeLine)
                    .font(.system(size: 11, design: status == nil ? .monospaced : .default))
                    .foregroundStyle(status == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(theme.accent))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: status)
            }

            HStack(spacing: 6) {
                Button("Copy") {
                    Clipboard.copyFile(capture)
                    flash(capture.kind.isVideo ? "Video copied" : "Image copied")
                }
                .buttonStyle(QuietButtonStyle())
                .fixedSize()
                Button(isUploading ? "Preparing..." : "Copy Link") { share() }
                    .buttonStyle(QuietButtonStyle())
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
        }
        .task(id: capture.fileURL) {
            thumbnail = await Library.thumbnail(for: capture, size: CGSize(width: 320, height: 180))
            if capture.kind.isVideo, let seconds = try? await AVURLAsset(url: capture.fileURL).load(.duration).seconds,
               seconds.isFinite {
                duration = BufferMath.clock(Int(seconds.rounded()))
            }
        }
    }

    private var timeLine: String {
        let date = capture.createdAt
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Today \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday \(time)" }
        return date.formatted(.dateTime.day().month(.abbreviated)) + " " + time
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
