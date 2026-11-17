import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class CaptureController: ObservableObject {
    @Published private(set) var isBuffering = false
    @Published private(set) var isRecording = false
    @Published private(set) var isSavingClip = false
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
        if Preferences.shared.startsBufferOnLaunch {
            startBuffer()
        }
    }

    func startBuffer() {
        Task {
            do {
                let prefs = Preferences.shared
                try await replay.start(seconds: prefs.clipSeconds, quality: prefs.clipQuality, includeMicrophone: recordsMicrophone)
                isBuffering = true
            } catch {
                present(error)
            }
        }
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
