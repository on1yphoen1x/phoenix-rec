import AVFoundation
import CoreMedia

struct Highlight: Identifiable, Equatable {
    enum Kind {
        case loud
        case marked

        var title: String {
            switch self {
            case .loud: "Loud moment"
            case .marked: "Marked"
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let date: Date
}

// Watches the game audio for a sudden jump in loudness compared with the last
// few seconds: an explosion, a kill sound, everyone shouting at once. Quiet
// games and steady music don't trigger it because the baseline follows them.
struct LoudnessDetector {
    private var baseline: Float = -60
    private var shortTerm: Float = -90
    private var heard: Double = 0
    private var lastHit: Double = -.infinity

    private let warmUp: Double = 4
    private let cooldown: Double = 10
    private let jump: Float = 14
    private let floor: Float = -30

    mutating func reset() {
        self = LoudnessDetector()
    }

    mutating func process(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let level = Self.level(of: sampleBuffer) else { return false }
        let duration = max(0.001, sampleBuffer.duration.seconds.isFinite ? sampleBuffer.duration.seconds : 0.01)
        heard += duration

        shortTerm = 0.6 * shortTerm + 0.4 * level
        let isHit = heard > warmUp
            && heard - lastHit > cooldown
            && shortTerm > floor
            && shortTerm > baseline + jump

        // Spikes barely move the baseline, otherwise one long fight would hide
        // the next loud moment.
        let alpha = Float(min(1, duration / 8))
        baseline += alpha * (min(level, baseline + 6) - baseline)

        if isHit { lastHit = heard }
        return isHit
    }

    private static func level(of sampleBuffer: CMSampleBuffer) -> Float? {
        guard let format = sampleBuffer.formatDescription,
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              description.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              description.mBitsPerChannel == 32 else { return nil }

        var sizeNeeded = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &sizeNeeded, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
        guard sizeNeeded > 0 else { return nil }

        let raw = UnsafeMutableRawPointer.allocate(byteCount: sizeNeeded, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: sizeNeeded,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &block) == noErr else { return nil }

        var sum: Float = 0
        var count = 0
        for buffer in UnsafeMutableAudioBufferListPointer(list) {
            guard let data = buffer.mData else { continue }
            let samples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let pointer = data.assumingMemoryBound(to: Float.self)
            for index in 0..<samples {
                sum += pointer[index] * pointer[index]
            }
            count += samples
        }
        guard count > 0 else { return nil }
        let rms = (sum / Float(count)).squareRoot()
        return max(-90, 20 * log10(max(rms, 1e-9)))
    }
}
