import AppKit

@MainActor
final class Updater: ObservableObject {
    struct Release {
        let build: Int
        let downloadURL: URL
    }

    enum UpdateError: LocalizedError {
        case notInstalled
        case badArchive

        var errorDescription: String? {
            switch self {
            case .notInstalled: "Move Flint into the Applications folder first, then try updating again."
            case .badArchive: "The downloaded update didn't contain the app."
            }
        }
    }

    @Published private(set) var available: Release?
    @Published private(set) var isInstalling = false

    private let latestURL = URL(string: "https://api.github.com/repos/on1yphoen1x/phoenix-rec/releases/latest")!
    private var timer: Timer?

    var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    init() {
        startChecking()
    }

    private func startChecking() {
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    @discardableResult
    func check() async -> Bool {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let assets: [Asset]
        }

        var request = URLRequest(url: latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let build = Int(payload.tag_name.replacingOccurrences(of: "build-", with: "")),
              let asset = payload.assets.first(where: { $0.name == "Flint.zip" })
                ?? payload.assets.first(where: { $0.name == "Ember.zip" })
                ?? payload.assets.first(where: { $0.name == "Phoenix.zip" }) else { return false }

        available = build > currentBuild ? Release(build: build, downloadURL: asset.browser_download_url) : nil
        return true
    }

    func install() async throws {
        guard let release = available, !isInstalling else { return }

        let appURL = Bundle.main.bundleURL
        // Gatekeeper runs freshly downloaded apps from a read-only shadow copy,
        // which can't be replaced in place.
        guard !appURL.path.contains("AppTranslocation"),
              FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            throw UpdateError.notInstalled
        }

        isInstalling = true
        defer { isInstalling = false }

        let workFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlintUpdate-\(release.build)", isDirectory: true)
        try? FileManager.default.removeItem(at: workFolder)
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)

        let (downloaded, _) = try await URLSession.shared.download(from: release.downloadURL)
        let archive = workFolder.appendingPathComponent("Update.zip")
        try FileManager.default.moveItem(at: downloaded, to: archive)

        try await run("/usr/bin/ditto", ["-x", "-k", archive.path, workFolder.path])
        // The bundle inside the zip may have a different name from the installed
        // one; it still replaces the app at its current path.
        let contents = (try? FileManager.default.contentsOfDirectory(at: workFolder, includingPropertiesForKeys: nil)) ?? []
        guard let newApp = contents.first(where: { $0.pathExtension == "app" }),
              FileManager.default.fileExists(atPath: newApp.appendingPathComponent("Contents/MacOS").path) else {
            throw UpdateError.badArchive
        }

        // The swap has to happen after this process exits, so hand it to a shell
        // that waits for us to quit, replaces the bundle and reopens it.
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "$1.old" && mv "$1" "$1.old" && mv "$2" "$1" && rm -rf "$1.old"
        open "$1"
        """
        let swap = Process()
        swap.executableURL = URL(fileURLWithPath: "/bin/sh")
        swap.arguments = ["-c", script, "sh", appURL.path, newApp.path]
        try swap.run()

        NSApp.terminate(nil)
    }

    private func run(_ path: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
