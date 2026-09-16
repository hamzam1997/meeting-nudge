import AppKit
import EventKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    let eventKit = EventKitSource()
    private let notifier = Notifier()

    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var settings: SettingsWindow?

    /// Occurrences already alerted, so a repeating meeting nags once per instance.
    private var alerted = Set<String>()
    /// Occurrences the user pushed back to the meeting's start time.
    private var snoozed: [String: Date] = [:]

    private var nudge: Nudge?
    private var queue: [Meeting] = []

    private(set) var meetings: [Meeting] = []

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ note: Notification) {
        // Opt out of App Nap without also keeping the Mac awake.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                        reason: "Meeting alerts")
        Log.write("launched, lead \(Int(Prefs.leadTime / 60))m, style \(Prefs.alertStyle.rawValue)")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "calendar.badge.clock",
                                           accessibilityDescription: "MeetingNudge")
        statusItem.button?.imagePosition = .imageLeading
        rebuildMenu()

        notifier.prepare()
        notifier.onJoin = { [weak self] url in self?.open(url) }

        eventKit.observeChanges { [weak self] in self?.refresh() }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Log.write("woke from sleep, rereading calendars")
            self?.refresh()
            self?.tick()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 1

        refresh()

        // Without calendar access there is nothing to alert about, so say so
        // up front rather than sitting silently in the menu bar.
        if !Prefs.didOnboard || eventKit.authorizationStatus != .fullAccess {
            openSettings()
        }

        if CommandLine.arguments.contains("--preview") {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in self?.previewAlert() }
        }
    }

    // MARK: Data

    /// Re-read the calendar store. This is a local database query, so it runs
    /// on every tick: a one minute refresh gap could otherwise swallow a
    /// meeting added seconds before it starts.
    func refresh() {
        eventKit.refresh(muted: Prefs.mutedCalendars)

        let before = meetings.count
        var found = dedupeMeetings(eventKit.meetings).filter { $0.isAlertable }
        if Prefs.onlyWithJoinLink { found = found.filter { $0.joinURL != nil } }
        meetings = found

        if meetings.count != before {
            let next = meetings.first.map { "\($0.title) at \($0.start)" } ?? "none"
            Log.write("watching \(meetings.count) meetings, next: \(next)")
        }
        updateStatusTitle()
    }

    private func tick() {
        refresh()
        let now = Date()

        for meeting in meetings {
            let key = meeting.occurrenceID

            // A snoozed meeting comes back at its start time.
            if let wake = snoozed[key] {
                if now >= wake {
                    snoozed.removeValue(forKey: key)
                    Log.write("snooze expired: \(meeting.title)")
                    show(meeting)
                }
                continue
            }

            guard shouldAlert(start: meeting.start, now: now, leadTime: Prefs.leadTime) else { continue }
            guard !alerted.contains(key) else { continue }
            alerted.insert(key)
            Log.write("alerting: \(meeting.title) starts \(meeting.start)")
            show(meeting)
        }

        // Keep the dedupe set from growing without bound.
        if alerted.count > 500 { alerted.removeAll() }
        updateStatusTitle()
    }

    // MARK: Alerting

    private func show(_ meeting: Meeting) {
        if Prefs.alertStyle == .notification {
            notifier.post(meeting)
            return
        }
        // One overlay at a time; a clashing meeting waits its turn.
        guard nudge == nil else {
            if !queue.contains(where: { $0.occurrenceID == meeting.occurrenceID }) {
                queue.append(meeting)
            }
            return
        }
        nudge = Nudge(meeting: meeting, style: Prefs.alertStyle,
                      onJoin: { [weak self] in self?.join($0) },
                      onSnooze: { [weak self] in self?.snooze($0) },
                      onClose: { [weak self] in
                          guard let self else { return }
                          self.nudge = nil
                          if !self.queue.isEmpty { self.show(self.queue.removeFirst()) }
                      })
    }

    private func join(_ meeting: Meeting) {
        if let url = meeting.joinURL {
            Log.write("joining \(meeting.title) at \(url.host ?? "?")")
            open(url)
        } else {
            open(URL(string: "ical://")!)
        }
    }

    private func snooze(_ meeting: Meeting) {
        snoozed[meeting.occurrenceID] = meeting.start
        Log.write("snoozed \(meeting.title) until it starts")
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func requestNotificationAccess() {
        notifier.requestAuthorization()
    }

    @objc func previewAlert() {
        let sample = meetings.first ?? Meeting(
            externalID: "preview", title: "Sprint planning", start: Date().addingTimeInterval(60),
            end: Date().addingTimeInterval(1860), location: nil, notes: nil,
            urlString: "https://meet.google.com/abc-defg-hij", isAllDay: false,
            declined: false, isCancelled: false, calendarID: "preview", calendarTitle: "Preview",
            accountTitle: "Preview", colorHex: nil)
        if Prefs.alertStyle == .notification {
            notifier.requestAuthorization()
            notifier.post(sample)
            return
        }
        nudge?.close()
        nudge = nil
        show(sample)
    }

    // MARK: Menu bar

    var nextMeeting: Meeting? {
        meetings.first { $0.start.timeIntervalSinceNow > -30 }
    }

    private func updateStatusTitle() {
        guard let next = nextMeeting else {
            statusItem?.button?.title = ""
            return
        }
        let mins = Int(next.start.timeIntervalSinceNow / 60)
        statusItem?.button?.title = mins < 1 ? " now"
            : (mins < 60 ? " \(mins)m" : " \(mins / 60)h\(mins % 60)m")
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    private func rebuildMenu() {
        let menu = statusItem.menu ?? NSMenu()
        menu.removeAllItems()
        menu.autoenablesItems = false

        if eventKit.authorizationStatus != .fullAccess {
            menu.addItem(item("Set up MeetingNudge…", #selector(openSettings)))
        } else if let next = nextMeeting {
            let fmt = DateFormatter()
            fmt.timeStyle = .short
            menu.addItem(item("Next: \(next.title) at \(fmt.string(from: next.start))", #selector(openNext)))
        } else {
            let none = NSMenuItem(title: "No meetings coming up", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Preview alert", #selector(previewAlert)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MeetingNudge",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        if statusItem.menu !== menu { statusItem.menu = menu }
    }

    @objc private func openNext() {
        if let next = nextMeeting { join(next) } else { open(URL(string: "ical://")!) }
    }

    @objc func openSettings() {
        if settings == nil { settings = SettingsWindow(app: self) }
        settings?.show()
    }

    /// Clicking the app in Finder or the Dock reopens settings, since there is
    /// no main window to restore.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refresh()
        rebuildMenu()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
