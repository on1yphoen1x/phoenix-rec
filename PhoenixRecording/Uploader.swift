import Foundation

protocol Uploader {
    func upload(_ capture: Capture) async throws -> URL
}

enum UploadError: LocalizedError {
    case notConfigured
    case badResponse(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Sharing isn't set up yet. Paste your upload token into Settings > Sharing."
        case .badResponse(let status, let body):
            "Upload failed (\(status)): \(body)"
        }
    }
}

// Files go straight through the Worker into R2. The free plan caps a request
// at 100 MB, so ShareCompressor keeps every upload under that.
struct WorkerUploader: Uploader {
    let endpoint: URL
    let token: String

    private struct Ticket: Decodable {
        let shareURL: URL
    }

    var shrinksVideo = true

    func upload(_ capture: Capture) async throws -> URL {
        var fileURL = capture.fileURL
        if capture.kind.isVideo, try await ShareCompressor.needsCompressing(fileURL, shrinking: shrinksVideo) {
            fileURL = try await ShareCompressor.compress(fileURL)
        }
        defer {
            if fileURL != capture.fileURL { try? FileManager.default.removeItem(at: fileURL) }
        }

        let mimeType = capture.contentType.preferredMIMEType ?? "application/octet-stream"
        var request = URLRequest(url: endpoint.appendingPathComponent("upload"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        try check(response, data)
        return try JSONDecoder().decode(Ticket.self, from: data).shareURL
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw UploadError.badResponse(status, String(decoding: data.prefix(300), as: UTF8.self))
        }
    }
}

extension Preferences {
    func makeUploader() throws -> Uploader {
        guard let token = Keychain.read("uploadToken"), !token.isEmpty else {
            throw UploadError.notConfigured
        }
        return WorkerUploader(endpoint: uploadEndpoint ?? Preferences.defaultUploadEndpoint, token: token, shrinksVideo: shrinksSharedClips)
    }
}
