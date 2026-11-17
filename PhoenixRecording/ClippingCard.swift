import SwiftUI

struct ClippingCard: View {
    @ObservedObject var controller: CaptureController
    @Environment(\.theme) private var theme

    @State private var source = Preferences.shared.captureSource
    @State private var displayID = Preferences.shared.captureDisplayID
    @State private var windowID = Preferences.shared.captureWindowID
    @State private var appID = Preferences.shared.captureAppID
    @State private var audioSource = Preferences.shared.audioSource
    @State private var audioAppID = Preferences.shared.audioAppID

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 18) {
                startButton
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(statusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .animation(.easeOut(duration: 0.2), value: controller.isBuffering)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        controller.saveClip()
                    } label: {
                        Label("Save Clip", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!controller.isBuffering || controller.isSavingClip)
                    .fixedSize()
                    KeyCaps(keys: ["\u{2325}", "\u{21E7}", "C"])
                }
            }

            Divider().overlay(theme.border)

            VStack(alignment: .leading, spacing: 14) {
                pickerRow(title: "Record") {
                    Picker("", selection: $source) {
                        ForEach(CaptureSource.allCases) { option in
                            Label(option.rawValue, systemImage: option.symbol).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()

                    targetPicker
                }

                pickerRow(title: "Audio") {
                    Picker("", selection: $audioSource) {
                        ForEach(AudioSource.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()

                    if audioSource == .app {
                        optionPicker(selection: $audioAppID, options: controller.captureOptions.apps,
                                     placeholder: "Choose an app")
                    }

                    Toggle("Microphone", isOn: $controller.recordsMicrophone)
                        .toggleStyle(.checkbox)
                        .fixedSize()
                }
            }
        }
        .padding(22)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(controller.isBuffering ? theme.accent.opacity(0.6) : theme.border))
        .animation(.easeOut(duration: 0.25), value: controller.isBuffering)
        .onAppear { controller.refreshCaptureOptions() }
        .onChange(of: source) { _, value in
            Preferences.shared.captureSource = value
            fillDefaultTarget()
            controller.restartBufferIfRunning()
        }
        .onChange(of: displayID) { _, value in save { $0.captureDisplayID = value } }
        .onChange(of: windowID) { _, value in save { $0.captureWindowID = value } }
        .onChange(of: appID) { _, value in save { $0.captureAppID = value } }
        .onChange(of: audioSource) { _, value in
            Preferences.shared.audioSource = value
            fillDefaultTarget()
            controller.restartBufferIfRunning()
        }
        .onChange(of: audioAppID) { _, value in save { $0.audioAppID = value } }
        .onChange(of: controller.captureOptions.apps) { _, _ in fillDefaultTarget() }
    }

    private var startButton: some View {
        Button {
            controller.isBuffering ? controller.stopBuffer() : controller.startBuffer()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: controller.isBuffering ? "stop.fill" : "record.circle")
                    .font(.system(size: 16, weight: .semibold))
                Text(controller.isBuffering ? "Stop Clipping" : (controller.isStartingBuffer ? "Starting..." : "Start Clipping"))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(minWidth: 190)
            .background {
                RoundedRectangle(cornerRadius: 13)
                    .fill(controller.isBuffering ? AnyShapeStyle(Color.red.opacity(0.85)) : AnyShapeStyle(theme.accent.gradient))
            }
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .disabled(controller.isStartingBuffer)
        .fixedSize()
    }

    @ViewBuilder
    private var targetPicker: some View {
        switch source {
        case .screen:
            optionPicker(selection: $displayID, options: controller.captureOptions.displays, placeholder: "Main display")
        case .window:
            optionPicker(selection: $windowID, options: controller.captureOptions.windows, placeholder: "Choose a window")
        case .app:
            optionPicker(selection: $appID, options: controller.captureOptions.apps, placeholder: "Choose an app")
        }
    }

    private var statusTitle: String {
        if controller.isBuffering { return "Clipping \(controller.captureLabel)" }
        return "Not clipping"
    }

    private var statusDetail: String {
        let prefs = Preferences.shared
        if controller.isBuffering {
            return "Keeping the last \(prefs.clipSeconds) seconds at \(prefs.clipQuality.rawValue) 60 fps, ready to save."
        }
        return "Start clipping and Ember keeps the last \(prefs.clipSeconds) seconds, so you can save a moment after it happens."
    }

    private func pickerRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            content()
            Spacer(minLength: 0)
            Button {
                controller.refreshCaptureOptions()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh the list of windows and apps")
            .opacity(title == "Record" ? 1 : 0)
            .disabled(title != "Record")
        }
    }

    private func optionPicker(selection: Binding<String>, options: [CaptureOption], placeholder: String) -> some View {
        Picker("", selection: selection) {
            if !options.contains(where: { $0.id == selection.wrappedValue }) {
                Text(placeholder).tag(selection.wrappedValue)
            }
            ForEach(options) { option in
                Text(option.name).lineLimit(1).tag(option.id)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 280)
    }

    // Picking Window or App with nothing chosen yet selects the first one in the
    // list, so Start Clipping works straight away.
    private func fillDefaultTarget() {
        let options = controller.captureOptions
        if source == .window, !options.windows.contains(where: { $0.id == windowID }), let first = options.windows.first {
            windowID = first.id
        }
        if source == .app, !options.apps.contains(where: { $0.id == appID }), let first = options.apps.first {
            appID = first.id
        }
        if audioSource == .app, !options.apps.contains(where: { $0.id == audioAppID }), let first = options.apps.first {
            audioAppID = first.id
        }
    }

    private func save(_ update: (Preferences) -> Void) {
        update(Preferences.shared)
        controller.restartBufferIfRunning()
    }
}
