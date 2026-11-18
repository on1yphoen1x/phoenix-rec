import Foundation

/// Lets the Flint notch app show a live recording timer and pause or stop the recording.
@MainActor
final class RecordingBridge {
    enum Command: String {
        case pause, resume, stop, status, clip, record, startClipping, stopClipping
    }

    enum State: String {
        case recording, paused, idle
    }

    static let stateName = Notification.Name("app.phoenixclips.ember.recordingState")
    static let commandName = Notification.Name("app.phoenixclips.ember.command")
    static let clipSavedName = Notification.Name("app.phoenixclips.ember.clipSaved")

    var onCommand: ((Command) -> Void)?
    private var observer: NSObjectProtocol?

    init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.commandName, object: nil, queue: .main
        ) { [weak self] note in
            guard let action = note.userInfo?["action"] as? String,
                  let command = Command(rawValue: action) else { return }
            MainActor.assumeIsolated { self?.onCommand?(command) }
        }
    }

    func publish(_ state: State, elapsed: TimeInterval, clippingSince: Date?) {
        DistributedNotificationCenter.default().postNotificationName(
            Self.stateName,
            object: nil,
            userInfo: [
                "state": state.rawValue,
                "elapsed": elapsed,
                "sentAt": Date().timeIntervalSince1970,
                "clipping": clippingSince != nil,
                "clippingSince": clippingSince?.timeIntervalSince1970 ?? 0,
            ],
            deliverImmediately: true
        )
    }

    func announceClipSaved() {
        DistributedNotificationCenter.default().postNotificationName(
            Self.clipSavedName, object: nil, userInfo: nil, deliverImmediately: true
        )
    }
}
