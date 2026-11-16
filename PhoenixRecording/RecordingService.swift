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
    private var pickerContinuation: CheckedContinuation<SCContentFilter, Error>?
    private var finishContinuation: CheckedContinuation<Void, Error>?

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

        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = url
        recordingConfig.outputFileType = .mp4
        recordingConfig.videoCodecType = .h264

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        let output = SCRecordingOutput(configuration: recordingConfig, delegate: self)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()

        self.stream = stream
        self.output = output
        self.outputURL = url
    }

    func stop() async throws -> URL {
        guard let stream, let output, let outputURL else { throw RecordingError.notRecording }

        // stopCapture returns before the file is finalised; the recording
        // delegate tells us when the MP4 moov atom has actually been written.
        try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            Task {
                do {
                    try stream.removeRecordingOutput(output)
                    try await stream.stopCapture()
                } catch {
                    resumeFinish(with: error)
                }
            }
        }

        self.stream = nil
        self.output = nil
        self.outputURL = nil
        return outputURL
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
