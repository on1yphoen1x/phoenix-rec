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
            "Sharing isn't set up yet. Add an upload URL and token in Settings."
        case .badResponse(let status, let body):
            "Upload failed (\(status)): \(body)"
        }
    }
}

// The Worker only signs a short-lived R2 URL; the file itself goes straight to R2,
// which sidesteps the 100 MB request limit on Cloudflare's free plan.
struct WorkerUploader: Uploader {
    let endpoint: URL
    let token: String

    private struct Ticket: Decodable {
        let uploadURL: URL
        let shareURL: URL
    }

    var shrinksVideo = true

    func upload(_ capture: Capture) async throws -> URL {
        var fileURL = capture.fileURL
        if capture.kind.isVideo, shrinksVideo, try await ShareCompressor.needsCompressing(fileURL) {
            fileURL = try await ShareCompressor.compress(fileURL)
        }
        defer {
            if fileURL != capture.fileURL { try? FileManager.default.removeItem(at: fileURL) }
        }

        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let mimeType = capture.contentType.preferredMIMEType ?? "application/octet-stream"

        var ticketRequest = URLRequest(url: endpoint.appendingPathComponent("uploads"))
        ticketRequest.httpMethod = "POST"
        ticketRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        ticketRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        ticketRequest.httpBody = try JSONEncoder().encode([
            "extension": capture.fileURL.pathExtension,
            "contentType": mimeType,
            "size": String(size),
        ])

        let (ticketData, ticketResponse) = try await URLSession.shared.data(for: ticketRequest)
        try check(ticketResponse, ticketData)
        let ticket = try JSONDecoder().decode(Ticket.self, from: ticketData)

        var putRequest = URLRequest(url: ticket.uploadURL)
        putRequest.httpMethod = "PUT"
        putRequest.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let (putData, putResponse) = try await URLSession.shared.upload(for: putRequest, fromFile: fileURL)
        try check(putResponse, putData)

        return ticket.shareURL
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
        guard let endpoint = uploadEndpoint, let token = Keychain.read("uploadToken"), !token.isEmpty else {
            throw UploadError.notConfigured
        }
        return WorkerUploader(endpoint: endpoint, token: token, shrinksVideo: shrinksSharedClips)
    }
}
