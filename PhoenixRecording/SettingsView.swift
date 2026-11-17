import AppKit
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case clipping = "Clipping"
    case audio = "Audio"
    case sharing = "Sharing"
    case appearance = "Appearance"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .clipping: "record.circle"
        case .audio: "speaker.wave.2"
        case .sharing: "link"
        case .appearance: "paintpalette"
        }
    }

    var subtitle: String {
        switch self {
        case .clipping: "Clip length, quality and where captures are saved"
        case .audio: "What gets recorded and the sound when a clip saves"
        case .sharing: "Where Copy Link uploads to"
        case .appearance: "Themes for the Flint window"
        }
    }
}

struct SettingsTabBar: View {
    @Binding var selection: SettingsTab
    @Environment(\.theme) private var theme

    // Falls back to icons only when the window is too narrow, so labels never wrap.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabs(showsTitles: true)
            tabs(showsTitles: false)
        }
    }

    private func tabs(showsTitles: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Group {
                        if showsTitles {
                            Label(tab.rawValue, systemImage: tab.symbol)
                        } else {
                            Image(systemName: tab.symbol)
                        }
                    }
                        .font(.system(size: 13, weight: selection == tab ? .semibold : .regular))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .background {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(theme.accent.opacity(0.18))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.accent.opacity(0.5)))
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(tab.rawValue)
            }
        }
        .fixedSize()
        .padding(4)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(theme.border))
    }
}

struct SettingsCard<Content: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 36, height: 36)
                    .background(theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.border))
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            control
                .fixedSize()
        }
    }
}

struct SettingsView: View {
    @ObservedObject var controller: CaptureController
    let tab: SettingsTab
    @Binding var themeID: String

    @State private var saveFolder = Preferences.shared.saveFolder
    @State private var copiesAfterCapture = Preferences.shared.copiesAfterCapture
    @State private var clipSeconds = Preferences.shared.clipSeconds
    @State private var clipQuality = Preferences.shared.clipQuality
    @State private var startsBufferOnLaunch = Preferences.shared.startsBufferOnLaunch
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var endpoint = Preferences.shared.uploadEndpoint?.absoluteString ?? ""
    @State private var token = Keychain.read("uploadToken") ?? ""
    @State private var shrinksSharedClips = Preferences.shared.shrinksSharedClips
    @State private var sharingSaved = false
    @State private var playsSaveSound = Preferences.shared.playsSaveSound
    @State private var saveSoundName = Preferences.shared.saveSoundName
    @State private var saveSoundVolume = Preferences.shared.saveSoundVolume

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                switch tab {
                case .clipping: clipping
                case .audio: audio
                case .sharing: sharing
                case .appearance: appearance
                }
            }
            .padding(28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .onDisappear(perform: saveSharing)
    }

    @ViewBuilder
    private var clipping: some View {
        SettingsCard(symbol: "dot.circle.viewfinder", title: "Replay Buffer",
                     subtitle: "Flint keeps this much of your screen ready to save at any moment") {
            SettingRow(title: "Clip length") {
                Picker("", selection: $clipSeconds) {
                    ForEach([15, 30, 60, 90, 120], id: \.self) { Text("\($0) seconds") }
                }
                .labelsHidden()
                .fixedSize()
            }
            .onChange(of: clipSeconds) { _, value in
                Preferences.shared.clipSeconds = value
                controller.restartBufferIfRunning()
            }

            SettingRow(title: "Quality", detail: "4K clips are about three times the size of 1080p") {
                Picker("", selection: $clipQuality) {
                    ForEach(ClipQuality.allCases) { Text("\($0.rawValue) at 60 fps").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            .onChange(of: clipQuality) { _, value in
                Preferences.shared.clipQuality = value
                controller.restartBufferIfRunning()
            }

            SettingRow(title: "Start the replay buffer when Flint opens") {
                Toggle("", isOn: $startsBufferOnLaunch).toggleStyle(.switch).labelsHidden()
            }
            .onChange(of: startsBufferOnLaunch) { _, value in
                Preferences.shared.startsBufferOnLaunch = value
            }

            SettingRow(title: "Open Flint at login") {
                Toggle("", isOn: $opensAtLogin).toggleStyle(.switch).labelsHidden()
            }
            .onChange(of: opensAtLogin) { _, value in
                try? value ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            }
        }

        SettingsCard(symbol: "folder", title: "Saving", subtitle: "Where clips and screenshots go on this Mac") {
            SettingRow(title: "Save to", detail: saveFolder.path) {
                Button("Choose...") { chooseFolder() }
            }
            SettingRow(title: "Copy to the clipboard after each capture") {
                Toggle("", isOn: $copiesAfterCapture).toggleStyle(.switch).labelsHidden()
            }
            .onChange(of: copiesAfterCapture) { _, value in
                Preferences.shared.copiesAfterCapture = value
            }
        }

        SettingsCard(symbol: "keyboard", title: "Shortcuts", subtitle: "These work everywhere, including over full-screen games") {
            SettingRow(title: "Save clip") { KeyCaps(keys: ["\u{2325}", "\u{21E7}", "C"]) }
            SettingRow(title: "Screenshot an area") { KeyCaps(keys: ["\u{2325}", "\u{21E7}", "4"]) }
        }
    }

    @ViewBuilder
    private var audio: some View {
        SettingsCard(symbol: "waveform", title: "Recording", subtitle: "Game and app audio is always recorded") {
            SettingRow(title: "Record microphone", detail: "Saved as its own track and mixed in for shared copies") {
                Toggle("", isOn: $controller.recordsMicrophone).toggleStyle(.switch).labelsHidden()
            }
        }

        SettingsCard(symbol: "speaker.wave.2", title: "Clip Capture Sound", subtitle: "What plays when a clip is saved") {
            SettingRow(title: "Sound alerts", detail: "Play a sound when a clip is saved") {
                Toggle("", isOn: $playsSaveSound).toggleStyle(.switch).labelsHidden()
            }
            .onChange(of: playsSaveSound) { _, value in
                Preferences.shared.playsSaveSound = value
            }

            if playsSaveSound {
                SettingRow(title: "Volume", detail: "\(Int(saveSoundVolume * 100))%") {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $saveSoundVolume, in: 0...1)
                            .frame(width: 220)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                }
                .onChange(of: saveSoundVolume) { _, value in
                    Preferences.shared.saveSoundVolume = value
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(SaveSound.names, id: \.self) { name in
                        SoundOption(name: name, isSelected: saveSoundName == name) {
                            saveSoundName = name
                            Preferences.shared.saveSoundName = name
                            SaveSound.play(name)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sharing: some View {
        SettingsCard(symbol: "icloud.and.arrow.up", title: "Share Links",
                     subtitle: "Copy Link uploads to your own Cloudflare storage") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Upload URL").font(.callout)
                TextField("", text: $endpoint, prompt: Text("https://share.example.com"))
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Upload token").font(.callout)
                SecureField("", text: $token)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Button("Save") {
                    saveSharing()
                    sharingSaved = true
                }
                .buttonStyle(.borderedProminent)
                if sharingSaved {
                    Text("Saved").font(.callout).foregroundStyle(.secondary)
                }
            }
        }

        SettingsCard(symbol: "arrow.down.right.and.arrow.up.left", title: "Upload Size",
                     subtitle: "Your saved clips always stay full quality") {
            SettingRow(title: "Shrink clips to 1080p before sharing",
                       detail: "Shared copies are about half the size, so twice as many fit in the free 10 GB") {
                Toggle("", isOn: $shrinksSharedClips).toggleStyle(.switch).labelsHidden()
            }
            .onChange(of: shrinksSharedClips) { _, value in
                Preferences.shared.shrinksSharedClips = value
            }
        }
    }

    @ViewBuilder
    private var appearance: some View {
        SettingsCard(symbol: "paintpalette", title: "Colour Theme",
                     subtitle: "\(Theme.all.count) themes, all free. Scenic themes add artwork to the sidebar") {
            ForEach(Theme.Family.allCases, id: \.self) { family in
                VStack(alignment: .leading, spacing: 10) {
                    Text(family.rawValue)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                        ForEach(Theme.all.filter { $0.family == family }) { option in
                            ThemeOption(option: option, isSelected: themeID == option.id) {
                                themeID = option.id
                            }
                        }
                    }
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = saveFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Preferences.shared.saveFolder = url
        saveFolder = url
        controller.reloadLibrary()
    }

    private func saveSharing() {
        let trimmed = endpoint.trimmingCharacters(in: .whitespaces)
        Preferences.shared.uploadEndpoint = trimmed.isEmpty ? nil : URL(string: trimmed)
        Keychain.write(token, for: "uploadToken")
    }
}

struct ThemeOption: View {
    let option: Theme
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(option.swatch)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().stroke(.white.opacity(0.25)))
                Text(option.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                if option.scenery != .plain {
                    Image(systemName: "mountain.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(isSelected ? theme.accent.opacity(0.14) : theme.background,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? theme.accent : theme.border, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

struct SoundOption: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "speaker.wave.2.fill" : "bell")
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.secondary))
                Text(name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(isSelected ? theme.accent.opacity(0.14) : theme.background,
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .stroke(isSelected ? theme.accent : theme.border, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

struct KeyCaps: View {
    let keys: [String]
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 24, minHeight: 22)
                    .padding(.horizontal, 4)
                    .background(theme.background, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.border))
            }
        }
    }
}

enum SaveSound {
    static let names = ["Tink", "Glass", "Pop", "Ping", "Purr", "Hero", "Bottle", "Frog", "Funk", "Morse", "Submarine", "Blow"]

    static func play(_ name: String = Preferences.shared.saveSoundName) {
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.stop()
        sound.volume = Float(Preferences.shared.saveSoundVolume)
        sound.play()
    }
}
