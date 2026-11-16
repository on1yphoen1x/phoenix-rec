import Foundation
import UniformTypeIdentifiers

struct Capture: Identifiable, Equatable {
    enum Kind {
        case screenshot
        case clip
        case recording

        var isVideo: Bool { self != .screenshot }
    }

    let id = UUID()
    let kind: Kind
    let fileURL: URL
    let createdAt: Date

    var contentType: UTType {
        kind.isVideo ? .mpeg4Movie : .png
    }

    static func newFileURL(kind: Kind, in folder: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = formatter.string(from: Date())
        let name = switch kind {
        case .screenshot: "Screenshot \(stamp).png"
        case .clip: "Clip \(stamp).mp4"
        case .recording: "Recording \(stamp).mp4"
        }
        return folder.appendingPathComponent(name)
    }
}
