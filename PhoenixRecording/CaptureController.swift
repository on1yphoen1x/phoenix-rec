import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class CaptureController: ObservableObject {
    @Published private(set) var isBuffering = false
    @Published private(set) var isRecording = false
    @Published private(set) var isRecordingPaused = false
    @Published private(set) var isSavingClip = false
    @Published private(set) var needsScreenPermission = false
    @Published private(set) var isStartingBuffer = false
    @Published private(set) var captureOptions = CaptureOptions()
    @Published private(set) var isLoadingOptions = false
    @Published private(set) var captureLabel = ""
    @Published private(set) var bufferStartedAt: Date?
    @Published private(set) var lastCapture: Capture?
    @Published private(set) var captures: [Capture] = []
    @Published var section = MainSection.clips
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
    private var workspaceObservers: [NSObjectProtocol] = []
    private var autoStartedBundleID: String?
    private let bridge = RecordingBridge()
    private var recordedBeforePause: TimeInterval = 0
    private var recordingResumedAt: Date?
    private var recorderTask: Task<Void, Never>?

    init() {
        Preferences.shared.migrateDefaultFolder()
        hotKeys = [
            HotKey(keyCode: kVK_ANSI_C, modifiers: optionKey | shiftKey) { [weak self] in self?.saveClip() },
            HotKey(keyCode: kVK_ANSI_4, modifiers: optionKey | shiftKey) { [weak self] in self?.takeScreenshot(.area) },
        ]
        replay.onStop = { [weak self] error in
            Task { @MainActor in
                self?.isBuffering = false
                self?.bufferStartedAt = nil
                self?.present(error)
            }
        }
        bridge.onCommand = { [weak self] command in
            guard let self else { return }
            switch command {
            case .pause: pauseRecording()
            case .resume: resumeRecording()
            case .stop: if isRecording { stopRecording() }
            case .status: publishRecordingState()
            }
        }
        watchForAutoClipApps()
        if !CGPreflightScreenCaptureAccess() {
            needsScreenPermission = true
        } else {
            let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
            if let game = running.first(where: { Preferences.shared.autoClipApps.contains($0) }) {
                appLaunched(game)
            } else if Preferences.shared.startsBufferOnLaunch {
                startBuffer(quietly: true)
            }
        }
    }

    func startBuffer(quietly: Bool = false) {
        guard CGPreflightScreenCaptureAccess() else {
            needsScreenPermission = true
            section = .clips
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
                bufferStartedAt = Date()
                isBuffering = true
            } catch {
                if CGPreflightScreenCaptureAccess() {
                    if !quietly { present(error) }
                } else {
                    needsScreenPermission = true
                }
            }
        }
    }

    func refreshCaptureOptions() {
        guard CGPreflightScreenCaptureAccess() else { return }
        isLoadingOptions = true
        Task {
            if let options = try? await CaptureTarget.options() {
                captureOptions = options
            }
            isLoadingOptions = false
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
        autoStartedBundleID = nil
        Task {
            await replay.stop()
            isBuffering = false
            bufferStartedAt = nil
        }
    }

    func restartBufferIfRunning() {
        guard isBuffering else { return }
        Task {
            await replay.stop()
            isBuffering = false
            bufferStartedAt = nil
            startBuffer()
        }
    }

    func saveClip() {
        guard isBuffering, !isSavingClip else {
            if !isBuffering { NSSound.beep() }
            return
        }
        isSavingClip = true
        let source = currentSource()
        if Preferences.shared.playsSaveSound {
            SaveSound.play()
        }

        Task {
            defer { isSavingClip = false }
            do {
                let folder = try Preferences.shared.ensureSaveFolder()
                let url = Capture.newFileURL(kind: .clip, in: folder)
                try await replay.saveClip(to: url)
                let capture = Capture(kind: .clip, fileURL: url, createdAt: Date())
                Library.setSource(source, for: capture)
                if let source { Preferences.shared.remember(source) }
                finish(capture)
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
                isRecordingPaused = false
                recordedBeforePause = 0
                recordingResumedAt = Date()
                publishRecordingState()
            } catch RecordingService.RecordingError.cancelled {
                return
            } catch {
                present(error)
            }
        }
    }

    var recordingElapsed: TimeInterval {
        recordedBeforePause + (recordingResumedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    func pauseRecording() {
        guard isRecording, !isRecordingPaused else { return }
        recordedBeforePause = recordingElapsed
        recordingResumedAt = nil
        isRecordingPaused = true
        publishRecordingState()
        runInOrder { try await $0.pause() }
    }

    func resumeRecording() {
        guard isRecording, isRecordingPaused else { return }
        recordingResumedAt = Date()
        isRecordingPaused = false
        publishRecordingState()
        runInOrder { try $0.resume() }
    }

    func stopRecording() {
        isRecording = false
        isRecordingPaused = false
        recordingResumedAt = nil
        publishRecordingState()
        runInOrder { [weak self] recorder in
            let url = try await recorder.stop()
            self?.finish(Capture(kind: .recording, fileURL: url, createdAt: Date()))
        }
    }

    // Pause, resume and stop each wait for the previous one, because a pause
    // only finishes once its file has been written.
    private func runInOrder(_ step: @escaping (RecordingService) async throws -> Void) {
        let previous = recorderTask
        let recorder = recorder
        recorderTask = Task { [weak self] in
            await previous?.value
            do {
                try await step(recorder)
            } catch {
                self?.present(error)
            }
        }
    }

    private func publishRecordingState() {
        let state: RecordingBridge.State = !isRecording ? .idle : isRecordingPaused ? .paused : .recording
        bridge.publish(state, elapsed: isRecording ? recordingElapsed : 0)
    }

    func reloadLibrary() {
        captures = Library.load()
    }

    func trash(_ capture: Capture) {
        do {
            try FileManager.default.trashItem(at: capture.fileURL, resultingItemURL: nil)
            Library.setShareLink(nil, for: capture)
            Library.setSource(nil, for: capture)
            reloadLibrary()
        } catch {
            present(error)
        }
    }

    func showResult(for capture: Capture) {
        resultPanel.show(capture)
    }

    private func watchForAutoClipApps() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier else { return }
                Task { @MainActor in
                    self?.appLaunched(id)
                    try? await Task.sleep(for: .seconds(3))
                    self?.refreshCaptureOptions()
                }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier else { return }
                Task { @MainActor in
                    self?.appTerminated(id)
                    self?.refreshCaptureOptions()
                }
            },
        ]
    }

    // A game can take a while after launch before it has a window to record, so
    // this waits for one before switching the buffer over to it.
    private func appLaunched(_ bundleID: String) {
        let prefs = Preferences.shared
        guard prefs.autoClipApps.contains(bundleID), CGPreflightScreenCaptureAccess() else { return }
        if isBuffering, prefs.captureSource == .screen || (prefs.captureSource == .app && prefs.captureAppID == bundleID) {
            return
        }
        Task {
            for _ in 0..<30 {
                if await CaptureTarget.isRunning(bundleID) { break }
                try? await Task.sleep(for: .seconds(2))
            }
            guard await CaptureTarget.isRunning(bundleID) else { return }
            prefs.captureSource = .app
            prefs.captureAppID = bundleID
            if isBuffering {
                await replay.stop()
                isBuffering = false
                bufferStartedAt = nil
            }
            autoStartedBundleID = bundleID
            startBuffer(quietly: true)
            refreshCaptureOptions()
        }
    }

    private func appTerminated(_ bundleID: String) {
        guard autoStartedBundleID == bundleID else { return }
        stopBuffer()
    }

    // The game a clip came from: the picked app or window when recording one,
    // otherwise whatever app was in front when the clip was saved.
    private func currentSource() -> Library.Source? {
        let prefs = Preferences.shared
        switch prefs.captureSource {
        case .app:
            if let app = captureOptions.apps.first(where: { $0.id == prefs.captureAppID }) {
                return Library.Source(bundleID: app.id, name: app.name)
            }
        case .window:
            let bundleID = String(prefs.captureWindowID.split(separator: "\u{1F}").first ?? "")
            if let app = captureOptions.apps.first(where: { $0.id == bundleID }) {
                return Library.Source(bundleID: app.id, name: app.name)
            }
        case .screen:
            break
        }
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              let name = front.localizedName else { return nil }
        return Library.Source(bundleID: bundleID, name: name)
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
