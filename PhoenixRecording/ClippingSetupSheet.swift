import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClippingSetupSheet: View {
    @ObservedObject var controller: CaptureController
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var source = Preferences.shared.captureSource
    @State private var displayID = Preferences.shared.captureDisplayID
    @State private var windowID = Preferences.shared.captureWindowID
    @State private var appID = Preferences.shared.captureAppID
    @State private var audioSource = Preferences.shared.audioSource
    @State private var audioAppID = Preferences.shared.audioAppID
    @State private var search = ""
    @State private var autoClipApps = Preferences.shared.autoClipApps
    @State private var remembered = Preferences.shared.rememberedApps

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    captureSection
                    audioSection
                    if source != .screen {
                        targetListSection
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    autoClipSection
                }
                .padding(20)
                .animation(.easeOut(duration: 0.2), value: source)
                .animation(.easeOut(duration: 0.2), value: audioSource)
            }

            VStack(spacing: 10) {
                Button(action: start) {
                    Label(startTitle, systemImage: controller.isBuffering ? "checkmark" : "record.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.accent.gradient, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(!canStart)
                .opacity(canStart ? 1 : 0.5)

                Text("Ember keeps the last \(Preferences.shared.clipSeconds) seconds while clipping is on. Press \u{2325}\u{21E7}C to save them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if !controller.isBuffering {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 18)
        }
        .frame(width: 560, height: 620)
        .background(theme.background)
        .onAppear {
            controller.refreshCaptureOptions()
            fillDefaultTarget()
        }
        .onChange(of: source) { _, value in
            Preferences.shared.captureSource = value
            search = ""
            fillDefaultTarget()
            controller.restartBufferIfRunning()
        }
        .onChange(of: displayID) { _, value in save { $0.captureDisplayID = value } }
        .onChange(of: windowID) { _, value in
            save { $0.captureWindowID = value }
            remember(bundleID: String(value.split(separator: "\u{1F}").first ?? ""))
        }
        .onChange(of: appID) { _, value in
            if controller.captureOptions.apps.contains(where: { $0.id == value && !$0.isRunning }) {
                Preferences.shared.captureAppID = value
            } else {
                save { $0.captureAppID = value }
                remember(bundleID: value)
            }
        }
        .onChange(of: audioSource) { _, value in
            Preferences.shared.audioSource = value
            fillDefaultTarget()
            controller.restartBufferIfRunning()
        }
        .onChange(of: audioAppID) { _, value in
            save { $0.audioAppID = value }
            remember(bundleID: value)
        }
        .onChange(of: controller.captureOptions.apps) { _, _ in fillDefaultTarget() }
    }

    private var captureSection: some View {
        SetupSection {
            SetupRow(symbol: source.symbol, title: "Capture") {
                SegmentedChoice(selection: $source, options: CaptureSource.allCases) { $0.rawValue }
            }
            if source == .screen, controller.captureOptions.displays.count > 1 {
                SetupRow(symbol: "rectangle.on.rectangle", title: "Display") {
                    menuPicker(selection: $displayID, options: controller.captureOptions.displays, placeholder: "Main display")
                }
            }
        }
    }

    private var audioSection: some View {
        SetupSection {
            SetupRow(symbol: audioSource == .off ? "speaker.slash" : "speaker.wave.2", title: "Desktop Audio") {
                SegmentedChoice(selection: $audioSource, options: AudioSource.allCases) { $0.title }
            }
            if audioSource == .app {
                SetupRow(symbol: "app.badge", title: "Audio From") {
                    menuPicker(selection: $audioAppID, options: runningApps, placeholder: "Choose an app")
                }
            }
            SetupRow(symbol: controller.recordsMicrophone ? "mic" : "mic.slash", title: "Microphone") {
                Toggle("", isOn: $controller.recordsMicrophone)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }

    private var targetListSection: some View {
        SetupSection {
            SetupRow(symbol: source == .window ? "macwindow.on.rectangle" : "square.grid.2x2",
                     title: source == .window ? "Select Window" : "Select App",
                     subtitle: source == .window ? "Pick the window to capture" : "Every window of this app is captured") {
                Button {
                    controller.refreshCaptureOptions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh the list")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(source == .window ? "Search apps or window titles" : "Search apps", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(theme.background, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.border))

            targetList
        }
    }

    @ViewBuilder
    private var targetList: some View {
        let options = filteredTargets
        if options.isEmpty {
            HStack(spacing: 10) {
                if controller.isLoadingOptions {
                    ProgressView().controlSize(.small)
                    Text(source == .window ? "Loading windows..." : "Loading apps...")
                } else {
                    Text(search.isEmpty ? "Nothing open to record. If a game is missing, open it and press refresh." : "Nothing matches \"\(search)\".")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else {
            VStack(spacing: 2) {
                ForEach(options) { option in
                    TargetRow(option: option, bundleID: bundleID(of: option),
                              isSelected: option.id == selectedTarget.wrappedValue) {
                        selectedTarget.wrappedValue = option.id
                    }
                    .contextMenu {
                        if !option.isRunning {
                            Button("Forget \(option.name)") { forget(option.id) }
                        }
                    }
                }
            }
        }
    }

    private var selectedTarget: Binding<String> {
        source == .window ? $windowID : $appID
    }

    private var filteredTargets: [CaptureOption] {
        let options = source == .window ? controller.captureOptions.windows : controller.captureOptions.apps
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return options }
        return options.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var canStart: Bool {
        if controller.isBuffering { return true }
        if controller.isStartingBuffer { return false }
        switch source {
        case .screen: return true
        case .window: return controller.captureOptions.windows.contains { $0.id == windowID }
        case .app: return controller.captureOptions.apps.contains { $0.id == appID }
        }
    }

    private func bundleID(of option: CaptureOption) -> String {
        source == .window ? String(option.id.split(separator: "\u{1F}").first ?? "") : option.id
    }

    private var runningApps: [CaptureOption] {
        controller.captureOptions.apps.filter(\.isRunning)
    }

    private var selectedAppIsClosed: Bool {
        source == .app && controller.captureOptions.apps.contains { $0.id == appID && !$0.isRunning }
    }

    private var startTitle: String {
        if controller.isBuffering { return "Done" }
        return selectedAppIsClosed ? "Clip It When It Opens" : "Start Clipping"
    }

    private func start() {
        if selectedAppIsClosed {
            setAutoClip(appID, on: true)
        } else if !controller.isBuffering {
            controller.startBuffer()
        }
        dismiss()
    }

    private var autoClipSection: some View {
        let apps = remembered
        return SetupSection {
            SetupRow(symbol: "bolt.circle", title: "Auto-clip",
                     subtitle: "Start clipping when these open, and stop when they close") {
                EmptyView()
            }
            if apps.isEmpty {
                Text("Apps you pick above or save clips from show up here, even after you close them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(apps, id: \.bundleID) { app in
                        let isRunning = runningApps.contains { $0.id == app.bundleID }
                        HStack(spacing: 10) {
                            Image(nsImage: AppIconCache.icon(for: app.bundleID))
                                .resizable()
                                .frame(width: 22, height: 22)
                            Text(app.name)
                                .lineLimit(1)
                            Text(isRunning ? "Open" : "Not open")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Toggle("", isOn: Binding(
                                get: { autoClipApps.contains(app.bundleID) },
                                set: { setAutoClip(app.bundleID, on: $0) }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .contextMenu {
                            Button("Forget \(app.name)") { forget(app.bundleID) }
                        }
                    }
                }
            }
        }
    }

    private func setAutoClip(_ bundleID: String, on: Bool) {
        if on {
            autoClipApps.insert(bundleID)
        } else {
            autoClipApps.remove(bundleID)
        }
        Preferences.shared.autoClipApps = autoClipApps
        if on, let app = controller.captureOptions.apps.first(where: { $0.id == bundleID }), app.isRunning {
            Preferences.shared.remember(Library.Source(bundleID: app.id, name: app.name))
            remembered = Preferences.shared.rememberedApps
        }
    }

    private func remember(bundleID: String) {
        guard let app = runningApps.first(where: { $0.id == bundleID }) else { return }
        Preferences.shared.remember(Library.Source(bundleID: app.id, name: app.name))
        remembered = Preferences.shared.rememberedApps
    }

    private func forget(_ bundleID: String) {
        Preferences.shared.forget(bundleID)
        autoClipApps = Preferences.shared.autoClipApps
        remembered = Preferences.shared.rememberedApps
        controller.refreshCaptureOptions()
    }

    private func menuPicker(selection: Binding<String>, options: [CaptureOption], placeholder: String) -> some View {
        Picker("", selection: selection) {
            if !options.contains(where: { $0.id == selection.wrappedValue }) {
                Text(placeholder).tag(selection.wrappedValue)
            }
            ForEach(options) { option in
                Text(option.name).lineLimit(1).tag(option.id)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 240)
    }

    // Window and App start with the first entry chosen, so Start Clipping works
    // without an extra click.
    private func fillDefaultTarget() {
        let options = controller.captureOptions
        if source == .window, !options.windows.contains(where: { $0.id == windowID }), let first = options.windows.first {
            windowID = first.id
        }
        if source == .app, !options.apps.contains(where: { $0.id == appID }), let first = options.apps.first(where: \.isRunning) {
            appID = first.id
        }
        if audioSource == .app, !runningApps.contains(where: { $0.id == audioAppID }), let first = runningApps.first {
            audioAppID = first.id
        }
    }

    private func save(_ update: (Preferences) -> Void) {
        update(Preferences.shared)
        controller.restartBufferIfRunning()
    }
}

struct SetupSection<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.border))
    }
}

struct SetupRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var subtitle: String?
    @ViewBuilder let trailing: Trailing
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 12)
            trailing
        }
    }
}

struct SegmentedChoice<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    @Environment(\.theme) private var theme
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? theme.onAccent : Color.primary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(theme.accent)
                                    .matchedGeometryEffect(id: "highlight", in: highlight)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(theme.background, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.border))
    }
}

struct TargetRow: View {
    let option: CaptureOption
    let bundleID: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: AppIconCache.icon(for: bundleID))
                    .resizable()
                    .frame(width: 22, height: 22)
                Text(option.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(option.isRunning ? Color.primary : Color.secondary)
                if !option.isRunning {
                    Text("Not open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? theme.accent.opacity(0.16) : (isHovering ? Color.primary.opacity(0.05) : .clear))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

@MainActor
enum AppIconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage {
        if let cached = icons[bundleID] { return cached }
        let icon: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSWorkspace.shared.icon(for: .application)
        }
        icons[bundleID] = icon
        return icon
    }
}
