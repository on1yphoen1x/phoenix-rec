import AppKit
import QuickLookThumbnailing

// The library is just the captures folder on disk. Share links and the game
// each clip came from are the only extra state, kept in UserDefaults by file name.
enum Library {
    struct Source: Hashable {
        let bundleID: String
        let name: String
    }

    private static let linksKey = "shareLinks"
    private static let sourcesKey = "clipSources"

    static func source(for capture: Capture) -> Source? {
        let sources = UserDefaults.standard.dictionary(forKey: sourcesKey) as? [String: [String]] ?? [:]
        guard let pair = sources[capture.fileURL.lastPathComponent], pair.count == 2 else { return nil }
        return Source(bundleID: pair[0], name: pair[1])
    }

    static func setSource(_ source: Source?, for capture: Capture) {
        var sources = UserDefaults.standard.dictionary(forKey: sourcesKey) as? [String: [String]] ?? [:]
        sources[capture.fileURL.lastPathComponent] = source.map { [$0.bundleID, $0.name] }
        UserDefaults.standard.set(sources, forKey: sourcesKey)
    }

    static func load() -> [Capture] {
        let folder = Preferences.shared.saveFolder
        let keys: [URLResourceKey] = [.creationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []

        return files.compactMap { url -> Capture? in
            guard let kind = kind(for: url) else { return nil }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return Capture(kind: kind, fileURL: url, createdAt: created)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    static func size(of capture: Capture) -> Int {
        (try? capture.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    static func shareLink(for capture: Capture) -> URL? {
        let links = UserDefaults.standard.dictionary(forKey: linksKey) as? [String: String] ?? [:]
        return links[capture.fileURL.lastPathComponent].flatMap(URL.init(string:))
    }

    static func setShareLink(_ link: URL?, for capture: Capture) {
        var links = UserDefaults.standard.dictionary(forKey: linksKey) as? [String: String] ?? [:]
        links[capture.fileURL.lastPathComponent] = link?.absoluteString
        UserDefaults.standard.set(links, forKey: linksKey)
    }

    // Returns the existing link if the capture was shared before, so pressing
    // Copy Link twice never uploads the same file twice.
    static func share(_ capture: Capture) async throws -> URL {
        if let existing = shareLink(for: capture) { return existing }
        let url = try await Preferences.shared.makeUploader().upload(capture)
        setShareLink(url, for: capture)
        return url
    }

    static func thumbnail(for capture: Capture, size: CGSize) async -> NSImage? {
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        let request = QLThumbnailGenerator.Request(
            fileAt: capture.fileURL, size: size, scale: scale, representationTypes: .thumbnail
        )
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }

    private static func kind(for url: URL) -> Capture.Kind? {
        let name = url.lastPathComponent
        switch url.pathExtension.lowercased() {
        case "png": return name.hasPrefix("Screenshot") ? .screenshot : nil
        case "mp4": return name.hasPrefix("Recording") ? .recording : .clip
        default: return nil
        }
    }
}
