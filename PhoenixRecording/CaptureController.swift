import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class CaptureController: ObservableObject {
    @Published private(set) var isBuffering = false
    @Published private(set) var isRecording = false
    @Published private(set) var isSavingClip = false
    @Published private(set) var needsScreenPermission = false
    @Published private(set) var isStartingBuffer = false
    @Published private(set) var captureOptions = CaptureOptions()
    @Published private(set) var captureLabel = ""
    @Published private(set) var lastCapture: Capture?
    @Published private(set) var captures: [Capture] = []
    @Published var section = MainSection.dashboard
    @Published var recordsMicrophone = Preferences.shared.recordsMicrophone {
        didSet {
            Preferences.shared.recordsMicrophone = recordsMicrophone
            restartBufferIfRunning()
        }
    }

    private let screenshots = ScreenshotService()
    private let recorder = RecordingService()
    private let replay = ReplayBuffer()
    private let resultPanel = ResultPanelController()
    private var hotKeys: [HotKey] = []

    init() {
        Preferences.shared.migrateDefaultFolder()
        hotKeys = [
            HotKey(keyCode: kVK_ANSI_C, modifiers: optionKey | shiftKey) { [weak self] in self?.saveClip() },
            HotKey(keyCode: kVK_ANSI_4, modifiers: optionKey | shiftKey) { [weak self] in self?.takeScreenshot(.area) },
        ]
        replay.onStop = { [weak self] error in
            Task { @MainActor in
                self?.isBuffering = false
                self?.present(error)
            }
        }
        if !CGPreflightScreenCaptureAccess() {
            needsScreenPermission = true
        } else if Preferences.shared.startsBufferOnLaunch {
            startBuffer()
        }
    }

    func startBuffer() {
        guard CGPreflightScreenCaptureAccess() else {
            needsScreenPermission = true
            section = .dashboard
            return
        }
        guard !isStartingBuffer else { return }
        isStartingBuffer = true
        Task {
            defer { isStartingBuffer = false }
            do {
                let prefs = Preferences.shared
                let target = try await CaptureTarget.resolve()
                try await replay.start(seconds: prefs.clipSeconds, quality: prefs.clipQuality,
                                       includeMicrophone: recordsMicrophone, video: target.video, audio: target.audio)
                captureLabel = target.label
                isBuffering = true
            } catch {
                if CGPreflightScreenCaptureAccess() {
                    present(error)
                } else {
                    needsScreenPermission = true
                }
            }
        }
    }

    func refreshCaptureOptions() {
        guard CGPreflightScreenCaptureAccess() else { return }
        Task {
            if let options = try? await CaptureTarget.options() {
                captureOptions = options
            }
        }
    }

    func requestScreenPermission() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // macOS only applies a new Screen Recording grant after the app restarts.
    func relaunch() {
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
        reopen.arguments = ["-c", "sleep 1; open \"$0\"", Bundle.main.bundleURL.path]
        try? reopen.run()
        NSApp.terminate(nil)
    }

    func stopBuffer() {
        Task {
            await replay.stop()
            isBuffering = false
        }
    }

    func restartBufferIfRunning() {
        guard isBuffering else { return }
        Task {
            await replay.stop()
            isBuffering = false
            startBuffer()
        }
    }

    func saveClip() {
        guard isBuffering, !isSavingClip else {
            if !isBuffering { NSSound.beep() }
            return
        }
        isSavingClip = true
        if Preferences.shared.playsSaveSound {
            SaveSound.play()
        }

        Task {
            defer { isSavingClip = false }
            do {
                let folder = try Preferences.shared.ensureSaveFolder()
                let url = Capture.newFileURL(kind: .clip, in: folder)
                try await replay.saveClip(to: url)
                finish(Capture(kind: .clip, fileURL: url, createdAt: Date()))
            } catch {
                present(error)
            }
        }
    }

    func takeScreenshot(_ mode: ScreenshotService.Mode) {
        Task {
            do {
                let folder = try Preferences.shared.ensureSaveFolder()
                let url = Capture.newFileURL(kind: .screenshot, in: folder)
                guard try await screenshots.capture(mode, to: url) else { return }
                finish(Capture(kind: .screenshot, fileURL: url, createdAt: Date()))
            } catch {
                present(error)
            }
        }
    }

    func startRecording() {
        Task {
            do {
                let folder = try Preferences.shared.ensureSaveFolder()
                let url = Capture.newFileURL(kind: .recording, in: folder)
                try await recorder.start(to: url, includeMicrophone: recordsMicrophone)
                isRecording = true
            } catch RecordingService.RecordingError.cancelled {
                return
            } catch {
                present(error)
            }
        }
    }

    func stopRecording() {
        Task {
            do {
                let url = try await recorder.stop()
                isRecording = false
                finish(Capture(kind: .recording, fileURL: url, createdAt: Date()))
            } catch {
                isRecording = false
                present(error)
            }
        }
    }

    func reloadLibrary() {
        captures = Library.load()
    }

    func trash(_ capture: Capture) {
        do {
            try FileManager.default.trashItem(at: capture.fileURL, resultingItemURL: nil)
            Library.setShareLink(nil, for: capture)
            reloadLibrary()
        } catch {
            present(error)
        }
    }

    func showResult(for capture: Capture) {
        resultPanel.show(capture)
    }

    private func finish(_ capture: Capture) {
        lastCapture = capture
        reloadLibrary()
        if Preferences.shared.copiesAfterCapture {
            Clipboard.copyFile(capture)
        }
        resultPanel.show(capture)
    }

    func present(_ error: Error) {
        let alert = NSAlert(error: error)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
