import AppKit
import ScreenCaptureKit

enum CaptureSource: String, CaseIterable, Identifiable {
    case screen = "Screen"
    case window = "Window"
    case app = "App"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .screen: "display"
        case .window: "macwindow"
        case .app: "app.dashed"
        }
    }
}

enum AudioSource: String, CaseIterable, Identifiable {
    case all = "All Audio"
    case app = "App Audio"
    case off = "Off"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .app: "App Only"
        case .off: "Off"
        }
    }
}

struct CaptureOption: Identifiable, Hashable {
    let id: String
    let name: String
    var isRunning = true
}

struct CaptureOptions {
    var displays: [CaptureOption] = []
    var windows: [CaptureOption] = []
    var apps: [CaptureOption] = []
}

enum CaptureTargetError: LocalizedError {
    case noDisplay
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay: "Couldn't find a display to record."
        case .missing(let what): "\(what) isn't open. Open it first, or turn on Auto-clip for it in Ember's clip settings."
        }
    }
}

// Turns the saved Record and Audio choices into ScreenCaptureKit filters. Video
// and audio get separate filters so you can, say, record the whole screen but
// only hear the game.
enum CaptureTarget {
    struct Resolved {
        let video: SCContentFilter
        let audio: SCContentFilter?
        let label: String
    }

    static func windowID(bundleID: String, title: String) -> String {
        "\(bundleID)\u{1F}\(title)"
    }

    static func options() async throws -> CaptureOptions {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let names = await displayNames()

        let windows = recordableWindows(in: content)
        let displays = content.displays.enumerated().map { index, display in
            CaptureOption(id: String(display.displayID),
                          name: names[display.displayID] ?? "Display \(index + 1)")
        }
        var seenWindows = Set<String>()
        let windowOptions = windows
            .map { window in
                CaptureOption(id: windowID(bundleID: window.owningApplication?.bundleIdentifier ?? "", title: window.title ?? ""),
                              name: windowName(window))
            }
            .filter { seenWindows.insert($0.id).inserted }

        var seen = Set<String>()
        let apps = windows.compactMap { $0.owningApplication }
            .filter { seen.insert($0.bundleIdentifier).inserted }
            .map { CaptureOption(id: $0.bundleIdentifier, name: $0.applicationName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let closed = Preferences.shared.rememberedApps
            .filter { remembered in !apps.contains { $0.id == remembered.bundleID } }
            .map { CaptureOption(id: $0.bundleID, name: $0.name, isRunning: false) }

        return CaptureOptions(displays: displays, windows: windowOptions, apps: apps + closed)
    }

    static func isRunning(_ bundleID: String) async -> Bool {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else {
            return false
        }
        return recordableWindows(in: content).contains { $0.owningApplication?.bundleIdentifier == bundleID }
    }

    static func resolve() async throws -> Resolved {
        let prefs = Preferences.shared
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let names = await displayNames()
        let mainID = await MainActor.run {
            NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        }

        guard let display = content.displays.first(where: { String($0.displayID) == prefs.captureDisplayID })
                ?? content.displays.first(where: { $0.displayID == mainID })
                ?? content.displays.first else {
            throw CaptureTargetError.noDisplay
        }
        let ownApp = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let wholeDisplay = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])

        let video: SCContentFilter
        let label: String
        switch prefs.captureSource {
        case .screen:
            video = wholeDisplay
            label = names[display.displayID] ?? "Screen"
        case .window:
            let windows = recordableWindows(in: content)
            let saved = prefs.captureWindowID.split(separator: "\u{1F}", maxSplits: 1).map(String.init)
            let bundleID = saved.first ?? ""
            let title = saved.count > 1 ? saved[1] : ""
            guard let window = windows.first(where: { $0.owningApplication?.bundleIdentifier == bundleID && $0.title == title })
                    ?? windows.first(where: { $0.owningApplication?.bundleIdentifier == bundleID }) else {
                throw CaptureTargetError.missing(title.isEmpty ? "The window you picked" : "\"\(title)\"")
            }
            video = SCContentFilter(desktopIndependentWindow: window)
            label = windowName(window)
        case .app:
            guard let app = content.applications.first(where: { $0.bundleIdentifier == prefs.captureAppID }) else {
                throw CaptureTargetError.missing("The app you picked")
            }
            let appDisplay = displayShowing(app, in: content) ?? display
            video = SCContentFilter(display: appDisplay, including: [app], exceptingWindows: [])
            label = app.applicationName
        }

        let audio: SCContentFilter?
        switch prefs.audioSource {
        case .all:
            audio = wholeDisplay
        case .app:
            guard let app = content.applications.first(where: { $0.bundleIdentifier == prefs.audioAppID }) else {
                throw CaptureTargetError.missing("The app you picked for audio")
            }
            audio = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        case .off:
            audio = nil
        }

        return Resolved(video: video, audio: audio, label: label)
    }

    // Off-screen windows count too: a game in full screen sits in its own Space,
    // so it is "off screen" whenever Ember's window is in front. Games like Roblox
    // can also leave their window title empty, so the app name stands in for it.
    private static func recordableWindows(in content: SCShareableContent) -> [SCWindow] {
        content.windows.filter { window in
            guard let app = window.owningApplication,
                  !app.bundleIdentifier.isEmpty,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier,
                  !systemApps.contains(app.bundleIdentifier) else { return false }
            // Some games that launch straight into full screen put their window
            // above the normal layer, so a window covering a whole display counts too.
            let coversDisplay = content.displays.contains { $0.frame.size == window.frame.size }
            guard window.windowLayer == 0 || coversDisplay else { return false }
            return window.frame.width >= 200 && window.frame.height >= 150
        }
    }

    private static let systemApps: Set<String> = [
        "com.apple.dock", "com.apple.WindowManager", "com.apple.controlcenter",
        "com.apple.notificationcenterui", "com.apple.Spotlight", "com.apple.systemuiserver",
        "com.apple.screencaptureui", "com.apple.wallpaper.agent",
    ]

    private static func windowName(_ window: SCWindow) -> String {
        let app = window.owningApplication?.applicationName ?? "App"
        guard let title = window.title, !title.isEmpty, title != app else { return app }
        return "\(app) \u{00B7} \(title)"
    }

    private static func displayShowing(_ app: SCRunningApplication, in content: SCShareableContent) -> SCDisplay? {
        guard let frame = recordableWindows(in: content).first(where: { $0.owningApplication?.processID == app.processID })?.frame else {
            return nil
        }
        return content.displays.first { $0.frame.intersects(frame) }
    }

    @MainActor
    private static func displayNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                names[id] = screen.localizedName
            }
        }
        return names
    }
}
