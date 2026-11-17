import AVFoundation
import AppKit
import ScreenCaptureKit

enum ClipQuality: String, CaseIterable, Identifiable {
    case hd1080 = "1080p"
    case qhd1440 = "1440p"
    case uhd4K = "4K"

    var id: String { rawValue }

    var height: Int {
        switch self {
        case .hd1080: 1080
        case .qhd1440: 1440
        case .uhd4K: 2160
        }
    }

    var bitrate: Int {
        switch self {
        case .hd1080: 12_000_000
        case .qhd1440: 20_000_000
        case .uhd4K: 40_000_000
        }
    }
}

// Keeps the last few minutes of the main display on disk as short, self-contained
// MP4 segments. Saving a clip closes the open segment and stitches the newest ones
// together without re-encoding, so a 4K clip saves in about a second.
final class ReplayBuffer: NSObject {
    enum BufferError: LocalizedError {
        case noDisplay
        case notRunning
        case nothingRecorded

        var errorDescription: String? {
            switch self {
            case .noDisplay: "Couldn't find a display to record."
            case .notRunning: "The replay buffer isn't running."
            case .nothingRecorded: "Nothing has been recorded yet. Give it a few seconds and try again."
            }
        }
    }

    private struct Segment {
        let url: URL
        let start: CMTime
        var end: CMTime
    }

    private let segmentLength = CMTime(seconds: 5, preferredTimescale: 600)
    private let queue = DispatchQueue(label: "app.phoenixclips.phoenix.replay")
    private let workFolder: URL

    private var stream: SCStream?
    private var audioStream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var gameAudioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var current: Segment?
    private var finished: [Segment] = []

    private var clipLength: CMTime = .zero
    private var outputSize = CGSize.zero
    private var quality = ClipQuality.hd1080
    private var includeMicrophone = false

    var onStop: ((Error) -> Void)?

    override init() {
        workFolder = FileManager.default.temporaryDirectory.appendingPathComponent("ReplayBuffer", isDirectory: true)
        super.init()
    }

    func start(seconds: Int, quality: ClipQuality, includeMicrophone: Bool,
               video filter: SCContentFilter, audio audioFilter: SCContentFilter) async throws {
        try? FileManager.default.removeItem(at: workFolder)
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)

        let nativeHeight = max(2, Int(filter.contentRect.height * CGFloat(filter.pointPixelScale)))
        let nativeWidth = max(2, Int(filter.contentRect.width * CGFloat(filter.pointPixelScale)))
        let height = min(quality.height, nativeHeight) & ~1
        let width = max(2, (nativeWidth * height / nativeHeight) & ~1)

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 8
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.capturesAudio = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)

        // Audio runs on its own stream so it can follow a different filter from
        // the picture. Its video is the smallest ScreenCaptureKit allows and is
        // never read.
        let audioConfig = SCStreamConfiguration()
        audioConfig.width = 2
        audioConfig.height = 2
        audioConfig.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        audioConfig.capturesAudio = true
        audioConfig.excludesCurrentProcessAudio = true
        audioConfig.sampleRate = 48_000
        audioConfig.channelCount = 2
        audioConfig.captureMicrophone = includeMicrophone

        let audioStream = SCStream(filter: audioFilter, configuration: audioConfig, delegate: self)
        try audioStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        if includeMicrophone {
            try audioStream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        }

        queue.sync {
            self.clipLength = CMTime(seconds: Double(seconds), preferredTimescale: 600)
            self.outputSize = CGSize(width: width, height: height)
            self.quality = quality
            self.includeMicrophone = includeMicrophone
            self.finished = []
            self.current = nil
        }

        try await stream.startCapture()
        do {
            try await audioStream.startCapture()
        } catch {
            try? await stream.stopCapture()
            throw error
        }
        self.stream = stream
        self.audioStream = audioStream
    }

    func stop() async {
        try? await stream?.stopCapture()
        try? await audioStream?.stopCapture()
        stream = nil
        audioStream = nil
        await closeSegment()
        queue.sync { finished.removeAll() }
        try? FileManager.default.removeItem(at: workFolder)
    }

    func saveClip(to url: URL) async throws {
        guard stream != nil else { throw BufferError.notRunning }

        await closeSegment()
        let (segments, length) = queue.sync { (finished, clipLength) }
        guard !segments.isEmpty else { throw BufferError.nothingRecorded }

        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let gameTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let micTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var cursor = CMTime.zero
        for segment in segments {
            let asset = AVURLAsset(url: segment.url)
            guard let duration = try? await asset.load(.duration), duration > .zero else { continue }
            let range = CMTimeRange(start: .zero, duration: duration)

            if let video = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack?.insertTimeRange(range, of: video, at: cursor)
            }
            let audio = try await asset.loadTracks(withMediaType: .audio)
            if audio.indices.contains(0) { try gameTrack?.insertTimeRange(range, of: audio[0], at: cursor) }
            if audio.indices.contains(1) { try micTrack?.insertTimeRange(range, of: audio[1], at: cursor) }
            cursor = cursor + duration
        }

        for track in [gameTrack, micTrack] where track?.segments.isEmpty ?? true {
            if let track { composition.removeTrack(track) }
        }

        let start = max(.zero, cursor - length)
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw BufferError.nothingRecorded
        }
        export.timeRange = CMTimeRange(start: start, end: cursor)
        export.shouldOptimizeForNetworkUse = true
        try await export.export(to: url, as: .mp4)
    }

    private func closeSegment() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.finishCurrentWriter { continuation.resume() }
            }
        }
    }

    // Everything below runs on `queue`.

    private func beginSegment(at time: CMTime) {
        let url = workFolder.appendingPathComponent("\(UUID().uuidString).mp4")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }

        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: quality.bitrate,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        video.expectsMediaDataInRealTime = true
        writer.add(video)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 160_000,
        ]
        let game = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        game.expectsMediaDataInRealTime = true
        writer.add(game)

        var mic: AVAssetWriterInput?
        if includeMicrophone {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            mic = input
        }

        guard writer.startWriting() else { return }
        writer.startSession(atSourceTime: time)

        self.writer = writer
        videoInput = video
        gameAudioInput = game
        micInput = mic
        current = Segment(url: url, start: time, end: time)
    }

    private func finishCurrentWriter(completion: @escaping () -> Void) {
        guard let writer, var segment = current else {
            completion()
            return
        }

        self.writer = nil
        videoInput = nil
        gameAudioInput = nil
        micInput = nil
        current = nil

        writer.endSession(atSourceTime: segment.end)
        writer.finishWriting { [weak self] in
            guard let self else { return completion() }
            self.queue.async {
                if writer.status == .completed {
                    segment.end = max(segment.end, segment.start)
                    self.finished.append(segment)
                    self.trimSegments()
                } else {
                    try? FileManager.default.removeItem(at: segment.url)
                }
                completion()
            }
        }
    }

    private func trimSegments() {
        let keep = clipLength + segmentLength
        var total = CMTime.zero
        var cutoff = finished.count
        for index in finished.indices.reversed() {
            total = total + (finished[index].end - finished[index].start)
            cutoff = index
            if total >= keep { break }
        }
        for segment in finished[..<cutoff] {
            try? FileManager.default.removeItem(at: segment.url)
        }
        finished.removeFirst(cutoff)
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        // ScreenCaptureKit sends status-only buffers when nothing on screen changed.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete else { return }

        let time = sampleBuffer.presentationTimeStamp

        if let segment = current, time - segment.start >= segmentLength {
            finishCurrentWriter {}
        }
        if current == nil {
            beginSegment(at: time)
        }

        guard let videoInput, videoInput.isReadyForMoreMediaData else { return }
        if videoInput.append(sampleBuffer) {
            current?.end = time
        }
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput?) {
        guard let input, let segment = current,
              sampleBuffer.presentationTimeStamp >= segment.start,
              input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }
}

extension ReplayBuffer: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen: appendVideo(sampleBuffer)
        case .audio: appendAudio(sampleBuffer, to: gameAudioInput)
        case .microphone: appendAudio(sampleBuffer, to: micInput)
        @unknown default: break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let other = stream === self.stream ? audioStream : self.stream
        self.stream = nil
        audioStream = nil
        Task { try? await other?.stopCapture() }
        onStop?(error)
    }
}
