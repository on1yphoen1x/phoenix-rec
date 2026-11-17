import Foundation
import Security

final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    var saveFolder: URL {
        get {
            if let path = defaults.string(forKey: "saveFolder") {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            return movies.appendingPathComponent("Flint", isDirectory: true)
        }
        set { defaults.set(newValue.path, forKey: "saveFolder") }
    }

    static let defaultUploadEndpoint = URL(string: "https://flint.men/clip")!

    var uploadEndpoint: URL? {
        get { defaults.string(forKey: "uploadEndpoint").flatMap(URL.init(string:)) }
        set { defaults.set(newValue?.absoluteString, forKey: "uploadEndpoint") }
    }

    var copiesAfterCapture: Bool {
        get { defaults.object(forKey: "copiesAfterCapture") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "copiesAfterCapture") }
    }

    var clipSeconds: Int {
        get { defaults.object(forKey: "clipSeconds") as? Int ?? 30 }
        set { defaults.set(newValue, forKey: "clipSeconds") }
    }

    var clipQuality: ClipQuality {
        get { defaults.string(forKey: "clipQuality").flatMap(ClipQuality.init(rawValue:)) ?? .hd1080 }
        set { defaults.set(newValue.rawValue, forKey: "clipQuality") }
    }

    var recordsMicrophone: Bool {
        get { defaults.bool(forKey: "recordsMicrophone") }
        set { defaults.set(newValue, forKey: "recordsMicrophone") }
    }

    var shrinksSharedClips: Bool {
        get { defaults.object(forKey: "shrinksSharedClips") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "shrinksSharedClips") }
    }

    var playsSaveSound: Bool {
        get { defaults.object(forKey: "playsSaveSound") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "playsSaveSound") }
    }

    var saveSoundName: String {
        get { defaults.string(forKey: "saveSoundName") ?? "Tink" }
        set { defaults.set(newValue, forKey: "saveSoundName") }
    }

    var saveSoundVolume: Double {
        get { defaults.object(forKey: "saveSoundVolume") as? Double ?? 1 }
        set { defaults.set(newValue, forKey: "saveSoundVolume") }
    }

    var captureSource: CaptureSource {
        get { defaults.string(forKey: "captureSource").flatMap(CaptureSource.init(rawValue:)) ?? .screen }
        set { defaults.set(newValue.rawValue, forKey: "captureSource") }
    }

    var captureDisplayID: String {
        get { defaults.string(forKey: "captureDisplayID") ?? "" }
        set { defaults.set(newValue, forKey: "captureDisplayID") }
    }

    var captureWindowID: String {
        get { defaults.string(forKey: "captureWindowID") ?? "" }
        set { defaults.set(newValue, forKey: "captureWindowID") }
    }

    var captureAppID: String {
        get { defaults.string(forKey: "captureAppID") ?? "" }
        set { defaults.set(newValue, forKey: "captureAppID") }
    }

    var audioSource: AudioSource {
        get { defaults.string(forKey: "audioSource").flatMap(AudioSource.init(rawValue:)) ?? .all }
        set { defaults.set(newValue.rawValue, forKey: "audioSource") }
    }

    var audioAppID: String {
        get { defaults.string(forKey: "audioAppID") ?? "" }
        set { defaults.set(newValue, forKey: "audioAppID") }
    }

    var startsBufferOnLaunch: Bool {
        get { defaults.object(forKey: "startsBufferOnLaunch") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "startsBufferOnLaunch") }
    }

    // Clips saved under the app's earlier names live in ~/Movies/Ember or
    // ~/Movies/Phoenix; bring them across unless the user picked their own folder.
    func migrateDefaultFolder() {
        guard defaults.string(forKey: "saveFolder") == nil else { return }
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: saveFolder.path),
              let old = ["Ember", "Phoenix"]
                .map({ movies.appendingPathComponent($0, isDirectory: true) })
                .first(where: { fileManager.fileExists(atPath: $0.path) }) else { return }
        try? fileManager.moveItem(at: old, to: saveFolder)
    }

    func ensureSaveFolder() throws -> URL {
        let folder = saveFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

enum Keychain {
    private static let service = "app.phoenixclips.PhoenixRecording"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }

        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}
