import Foundation

/// How insistent the alert should be. You picked "give people the choice", so
/// this is a setting rather than a decision baked into the overlay.
enum AlertStyle: String, CaseIterable {
    case fullScreen
    case banner
    case notification

    var title: String {
        switch self {
        case .fullScreen: return "Full screen"
        case .banner: return "Corner banner"
        case .notification: return "Notification"
        }
    }

    var detail: String {
        switch self {
        case .fullScreen: return "Covers every display and blocks clicks until you answer."
        case .banner: return "A panel in the corner that floats above other apps."
        case .notification: return "A normal macOS notification with a Join button."
        }
    }
}

enum Prefs {
    private static let defaults = UserDefaults.standard

    /// How long before a meeting the alert fires, in seconds.
    static var leadTime: TimeInterval {
        get {
            let stored = defaults.double(forKey: "leadSeconds")
            return stored > 0 ? stored : 60
        }
        set { defaults.set(newValue, forKey: "leadSeconds") }
    }

    static let leadChoices: [TimeInterval] = [60, 120, 300, 600]

    static var alertStyle: AlertStyle {
        get { AlertStyle(rawValue: defaults.string(forKey: "alertStyle") ?? "") ?? .fullScreen }
        set { defaults.set(newValue.rawValue, forKey: "alertStyle") }
    }

    /// Seconds before an unanswered alert clears itself. Zero means never,
    /// which is the insistent option and comes with the obvious risk.
    static var autoDismiss: TimeInterval {
        get {
            if defaults.object(forKey: "autoDismiss") == nil { return 150 }
            return defaults.double(forKey: "autoDismiss")
        }
        set { defaults.set(newValue, forKey: "autoDismiss") }
    }

    static let autoDismissChoices: [TimeInterval] = [0, 30, 60, 150]

    static var snoozeEnabled: Bool {
        get { defaults.object(forKey: "snooze") == nil ? true : defaults.bool(forKey: "snooze") }
        set { defaults.set(newValue, forKey: "snooze") }
    }

    /// Skip calendar blocks that have nowhere to join, for people whose
    /// calendar is mostly focus time.
    static var onlyWithJoinLink: Bool {
        get { defaults.bool(forKey: "onlyWithJoinLink") }
        set { defaults.set(newValue, forKey: "onlyWithJoinLink") }
    }

    static var playSound: Bool {
        get { defaults.object(forKey: "playSound") == nil ? true : defaults.bool(forKey: "playSound") }
        set { defaults.set(newValue, forKey: "playSound") }
    }

    /// Calendars switched off, by source identifier.
    static var mutedCalendars: Set<String> {
        get { Set(defaults.stringArray(forKey: "mutedCalendars") ?? []) }
        set { defaults.set(Array(newValue), forKey: "mutedCalendars") }
    }

    static var didOnboard: Bool {
        get { defaults.bool(forKey: "didOnboard") }
        set { defaults.set(newValue, forKey: "didOnboard") }
    }
}
