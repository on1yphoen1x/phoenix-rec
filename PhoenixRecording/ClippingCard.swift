import SwiftUI

struct ClippingCard: View {
    @ObservedObject var controller: CaptureController
    @Environment(\.theme) private var theme
    @State private var showsSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                startButton
                VStack(alignment: .leading, spacing: 4) {
                    Text(controller.isBuffering ? "Clipping \(controller.captureLabel)" : "Not clipping")
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

            HStack(spacing: 18) {
                summaryItem(symbol: Preferences.shared.captureSource.symbol,
                            text: captureSummary)
                summaryItem(symbol: audioSymbol, text: audioSummary)
                Spacer(minLength: 12)
                Button {
                    showsSetup = true
                } label: {
                    Label("Clip Settings", systemImage: "slider.horizontal.3")
                }
                .fixedSize()
            }
        }
        .padding(22)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(controller.isBuffering ? theme.accent.opacity(0.6) : theme.border))
        .animation(.easeOut(duration: 0.25), value: controller.isBuffering)
        .onAppear { controller.refreshCaptureOptions() }
        .sheet(isPresented: $showsSetup) {
            ClippingSetupSheet(controller: controller)
                .environment(\.theme, theme)
                .tint(theme.accent)
                .preferredColorScheme(theme.isDark ? .dark : .light)
        }
    }

    private var startButton: some View {
        Button {
            if controller.isBuffering {
                controller.stopBuffer()
            } else {
                showsSetup = true
            }
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

    private var statusDetail: String {
        let prefs = Preferences.shared
        if controller.isBuffering {
            return "Keeping the last \(prefs.clipSeconds) seconds at \(prefs.clipQuality.rawValue) 60 fps, ready to save."
        }
        return "Start clipping and Flint keeps the last \(prefs.clipSeconds) seconds, so you can save a moment after it happens."
    }

    private var captureSummary: String {
        let prefs = Preferences.shared
        let options = controller.captureOptions
        switch prefs.captureSource {
        case .screen:
            return options.displays.first { $0.id == prefs.captureDisplayID }?.name ?? "Main display"
        case .window:
            return options.windows.first { $0.id == prefs.captureWindowID }?.name ?? "A window"
        case .app:
            return options.apps.first { $0.id == prefs.captureAppID }?.name ?? "An app"
        }
    }

    private var audioSummary: String {
        let prefs = Preferences.shared
        let desktop: String
        switch prefs.audioSource {
        case .all: desktop = "All audio"
        case .app: desktop = controller.captureOptions.apps.first { $0.id == prefs.audioAppID }?.name ?? "One app"
        case .off: desktop = "No desktop audio"
        }
        return controller.recordsMicrophone ? "\(desktop) + mic" : desktop
    }

    private var audioSymbol: String {
        Preferences.shared.audioSource == .off ? "speaker.slash" : "speaker.wave.2"
    }

    private func summaryItem(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
