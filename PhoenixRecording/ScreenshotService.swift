import Foundation

struct ScreenshotService {
    enum Mode {
        case area
        case window
        case fullScreen

        var arguments: [String] {
            switch self {
            case .area: ["-i", "-s"]
            case .window: ["-i", "-w"]
            case .fullScreen: ["-m"]
            }
        }
    }

    // The system tool gives us the native crosshair, window highlight and
    // Escape-to-cancel for free. A cancelled selection exits 0 but writes no file.
    func capture(_ mode: Mode, to url: URL) async throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-t", "png"] + mode.arguments + [url.path]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        return FileManager.default.fileExists(atPath: url.path)
    }
}
