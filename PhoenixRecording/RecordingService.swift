import AVFoundation
import ScreenCaptureKit

@MainActor
final class RecordingService: NSObject {
    enum RecordingError: LocalizedError {
        case cancelled
        case notRecording
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: "Recording was cancelled."
            case .notRecording: "No recording is in progress."
            case .failed(let reason): reason
            }
        }
    }

    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var outputURL: URL?
    private var parts: [URL] = []
    private var pickerContinuation: CheckedContinuation<SCContentFilter, Error>?
    private var finishContinuation: CheckedContinuation<Void, Error>?

    private(set) var isPaused = false

    func start(to url: URL, includeMicrophone: Bool) async throws {
        let filter = try await pickContent()

        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(filter.contentRect.width * scale)
        config.height = Int(filter.contentRect.height * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        config.capturesAudio = true
        config.captureMicrophone = includeMicrophone

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream
        outputURL = url
        parts = []
        isPaused = false
        do {
            try beginPart()
            try await stream.startCapture()
        } catch {
            self.stream = nil
            output = nil
            outputURL = nil
            throw error
        }
    }

    /// SCRecordingOutput can't pause, so a pause closes the current file and a resume
    /// starts a new one. The stream keeps running so resuming is instant.
    func pause() async throws {
        guard output != nil, !isPaused else { return }
        try await endPart()
        isPaused = true
    }

    func resume() throws {
        guard stream != nil, isPaused else { return }
        try beginPart()
        isPaused = false
    }

    func stop() async throws -> URL {
        guard let stream, let outputURL else { throw RecordingError.notRecording }

        if output != nil {
            try await endPart()
        }
        try? await stream.stopCapture()

        self.stream = nil
        self.outputURL = nil
        isPaused = false
        let recorded = parts
        parts = []
        try await join(recorded, into: outputURL)
        return outputURL
    }

    private func beginPart() throws {
        guard let stream else { throw RecordingError.notRecording }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmberRecording-\(UUID().uuidString).mp4")

        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = url
        recordingConfig.outputFileType = .mp4
        recordingConfig.videoCodecType = .h264

        let output = SCRecordingOutput(configuration: recordingConfig, delegate: self)
        try stream.addRecordingOutput(output)
        self.output = output
        parts.append(url)
    }

    // Removing the output returns before the file is finalised; the recording
    // delegate tells us when the MP4 moov atom has actually been written.
    private func endPart() async throws {
        guard let stream, let output else { return }
        self.output = nil
        try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            do {
                try stream.removeRecordingOutput(output)
            } catch {
                resumeFinish(with: error)
            }
        }
    }

    private func join(_ parts: [URL], into url: URL) async throws {
        let existing = parts.filter { FileManager.default.fileExists(atPath: $0.path) }
        defer { existing.forEach { try? FileManager.default.removeItem(at: $0) } }

        guard !existing.isEmpty else { throw RecordingError.failed("Nothing was recorded.") }
        if existing.count == 1 {
            try FileManager.default.moveItem(at: existing[0], to: url)
            return
        }

        let composition = AVMutableComposition()
        var tracks: [String: AVMutableCompositionTrack] = [:]
        var cursor = CMTime.zero
        for part in existing {
            let asset = AVURLAsset(url: part)
            guard let duration = try? await asset.load(.duration), duration > .zero else { continue }
            let range = CMTimeRange(start: .zero, duration: duration)
            // Tracks are matched by kind and order so system audio and the microphone stay separate.
            for type in [AVMediaType.video, .audio] {
                for (index, track) in try await asset.loadTracks(withMediaType: type).enumerated() {
                    let key = "\(type.rawValue)\(index)"
                    if tracks[key] == nil {
                        tracks[key] = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid)
                    }
                    try tracks[key]?.insertTimeRange(range, of: track, at: cursor)
                }
            }
            cursor = cursor + duration
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw RecordingError.failed("The recording couldn't be saved.")
        }
        try await export.export(to: url, as: .mp4)
    }

    private func pickContent() async throws -> SCContentFilter {
        let picker = SCContentSharingPicker.shared
        var pickerConfig = SCContentSharingPickerConfiguration()
        pickerConfig.allowedPickerModes = [.singleDisplay, .singleWindow, .singleApplication]
        picker.defaultConfiguration = pickerConfig
        picker.add(self)
        picker.isActive = true

        return try await withCheckedThrowingContinuation { continuation in
            pickerContinuation = continuation
            picker.present()
        }
    }

    private func resolvePicker(with result: Result<SCContentFilter, Error>) {
        let picker = SCContentSharingPicker.shared
        picker.remove(self)
        picker.isActive = false
        pickerContinuation?.resume(with: result)
        pickerContinuation = nil
    }

    private func resumeFinish(with error: Error? = nil) {
        if let error {
            finishContinuation?.resume(throwing: error)
        } else {
            finishContinuation?.resume()
        }
        finishContinuation = nil
    }
}

extension RecordingService: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in resolvePicker(with: .success(filter)) }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in resolvePicker(with: .failure(RecordingError.cancelled)) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in resolvePicker(with: .failure(error)) }
    }
}

extension RecordingService: SCStreamDelegate, SCRecordingOutputDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in resumeFinish(with: error) }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in resumeFinish() }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in resumeFinish(with: error) }
    }
}
