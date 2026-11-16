import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: CaptureController

    @State private var saveFolder = Preferences.shared.saveFolder
    @State private var copiesAfterCapture = Preferences.shared.copiesAfterCapture
    @State private var clipSeconds = Preferences.shared.clipSeconds
    @State private var clipQuality = Preferences.shared.clipQuality
    @State private var startsBufferOnLaunch = Preferences.shared.startsBufferOnLaunch
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var endpoint = Preferences.shared.uploadEndpoint?.absoluteString ?? ""
    @State private var token = Keychain.read("uploadToken") ?? ""
    @State private var shrinksSharedClips = Preferences.shared.shrinksSharedClips

    var body: some View {
        Form {
            Section("Clips") {
                Picker("Clip length", selection: $clipSeconds) {
                    ForEach([15, 30, 60, 90, 120], id: \.self) { Text("\($0) seconds") }
                }
                .onChange(of: clipSeconds) { _, value in
                    Preferences.shared.clipSeconds = value
                    controller.restartBufferIfRunning()
                }

                Picker("Quality", selection: $clipQuality) {
                    ForEach(ClipQuality.allCases) { Text("\($0.rawValue) at 60 fps").tag($0) }
                }
                .onChange(of: clipQuality) { _, value in
                    Preferences.shared.clipQuality = value
                    controller.restartBufferIfRunning()
                }

                Toggle("Turn on replay buffer when Phoenix opens", isOn: $startsBufferOnLaunch)
                    .onChange(of: startsBufferOnLaunch) { _, value in
                        Preferences.shared.startsBufferOnLaunch = value
                    }
                Toggle("Open Phoenix at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, value in
                        try? value ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
            }

            Section("Saving") {
                LabeledContent("Save to") {
                    HStack {
                        Text(saveFolder.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose...") { chooseFolder() }
                    }
                }
                Toggle("Copy to clipboard after each capture", isOn: $copiesAfterCapture)
                    .onChange(of: copiesAfterCapture) { _, value in
                        Preferences.shared.copiesAfterCapture = value
                    }
            }

            Section("Sharing") {
                TextField("Upload URL", text: $endpoint, prompt: Text("https://share.example.com"))
                    .onSubmit(saveSharing)
                SecureField("Upload token", text: $token)
                    .onSubmit(saveSharing)
                Toggle("Shrink clips to 1080p before sharing", isOn: $shrinksSharedClips)
                    .onChange(of: shrinksSharedClips) { _, value in
                        Preferences.shared.shrinksSharedClips = value
                    }
                Text("Shared copies are about half the size, so twice as many fit in the free 10 GB. Your saved clips stay full quality.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Save") { saveSharing() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onDisappear(perform: saveSharing)
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
    }

    private func saveSharing() {
        let trimmed = endpoint.trimmingCharacters(in: .whitespaces)
        Preferences.shared.uploadEndpoint = trimmed.isEmpty ? nil : URL(string: trimmed)
        Keychain.write(token, for: "uploadToken")
    }
}
