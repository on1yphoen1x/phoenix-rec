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
            return movies.appendingPathComponent("Phoenix", isDirectory: true)
        }
        set { defaults.set(newValue.path, forKey: "saveFolder") }
    }

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

    var startsBufferOnLaunch: Bool {
        get { defaults.object(forKey: "startsBufferOnLaunch") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "startsBufferOnLaunch") }
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
