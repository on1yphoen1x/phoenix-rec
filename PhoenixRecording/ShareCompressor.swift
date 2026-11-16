import AVFoundation

// Makes a smaller copy of a clip for uploading. The original on disk is never
// touched. Game and mic tracks are mixed into one, because browsers and Discord
// only ever play the first audio track of an MP4.
enum ShareCompressor {
    static let maxHeight = 1080
    static let videoBitrate = 6_000_000
    static let audioBitrate = 128_000

    static func needsCompressing(_ url: URL) async throws -> Bool {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return false }
        let (size, bitrate) = try await track.load(.naturalSize, .estimatedDataRate)
        let audioCount = try await asset.loadTracks(withMediaType: .audio).count
        return Int(size.height) > maxHeight || Int(bitrate) > videoBitrate + 1_000_000 || audioCount > 1
    }

    static func compress(_ source: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-\(UUID().uuidString).mp4")

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let (naturalSize, frameRate) = try await videoTrack.load(.naturalSize, .nominalFrameRate)

        let height = min(maxHeight, Int(naturalSize.height))
        let width = (Int(naturalSize.width) * height / Int(naturalSize.height)) & ~1

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        let videoOut = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        videoOut.alwaysCopiesSampleData = false
        reader.add(videoOut)

        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoBitrate,
                AVVideoExpectedSourceFrameRateKey: max(30, Int(frameRate.rounded())),
                AVVideoMaxKeyFrameIntervalKey: 120,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        writer.add(videoIn)

        var audioOut: AVAssetReaderAudioMixOutput?
        var audioIn: AVAssetWriterInput?
        if !audioTracks.isEmpty {
            let mix = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
            ])
            reader.add(mix)
            audioOut = mix

            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: audioBitrate,
            ])
            writer.add(input)
            audioIn = input
        }

        guard reader.startReading(), writer.startWriting() else {
            throw writer.error ?? reader.error ?? CocoaError(.fileWriteUnknown)
        }
        writer.startSession(atSourceTime: .zero)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await pump(from: videoOut, to: videoIn, label: "video") }
            if let audioOut, let audioIn {
                group.addTask { await pump(from: audioOut, to: audioIn, label: "audio") }
            }
        }

        if reader.status == .failed {
            writer.cancelWriting()
            throw reader.error ?? CocoaError(.fileReadUnknown)
        }
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
        return output
    }

    private static func pump(from output: AVAssetReaderOutput, to input: AVAssetWriterInput, label: String) async {
        let queue = DispatchQueue(label: "app.phoenixclips.phoenix.compress.\(label)")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard let buffer = output.copyNextSampleBuffer(), input.append(buffer) else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }
}
