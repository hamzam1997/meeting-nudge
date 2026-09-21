import AppKit
import EventKit
import ServiceManagement

/// NSClipView lays out from the bottom, which puts a stack view's first row at
/// the bottom of the scroller and makes a full list look empty.
final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

// MARK: - View builders

private let cardWidth: CGFloat = 480
private let rowWidth: CGFloat = cardWidth - 28

private func symbolView(_ name: String, size: CGFloat, color: NSColor) -> NSImageView {
    let view = NSImageView()
    view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .medium))
    view.contentTintColor = color
    view.setContentHuggingPriority(.required, for: .horizontal)
    return view
}

private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                   color: NSColor = .labelColor) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byTruncatingTail
    return field
}

private func wrapping(_ text: String, size: CGFloat = 11, color: NSColor = .tertiaryLabelColor) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.font = .systemFont(ofSize: size)
    field.textColor = color
    field.isSelectable = false
    field.translatesAutoresizingMaskIntoConstraints = false
    field.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
    return field
}

private func row(_ views: [NSView], spacing: CGFloat = 8, width: CGFloat = rowWidth) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.spacing = spacing
    stack.alignment = .centerY
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.widthAnchor.constraint(equalToConstant: width).isActive = true
    return stack
}

private func spring() -> NSView {
    let view = NSView()
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return view
}

private func separator() -> NSView {
    let box = NSBox()
    box.boxType = .separator
    box.translatesAutoresizingMaskIntoConstraints = false
    box.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
    return box
}

/// A titled, rounded container. `NSBox` follows light and dark mode on its own.
private func card(_ title: String, symbol: String, rows: [NSView]) -> NSView {
    let inner = NSStackView(views: rows)
    inner.orientation = .vertical
    inner.alignment = .leading
    inner.spacing = 10
    inner.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 14, right: 14)
    inner.translatesAutoresizingMaskIntoConstraints = false

    let box = NSBox()
    box.boxType = .custom
    box.fillColor = .controlBackgroundColor
    box.borderColor = .separatorColor
    box.borderWidth = 1
    box.cornerRadius = 10
    box.titlePosition = .noTitle
    box.contentViewMargins = .zero
    box.translatesAutoresizingMaskIntoConstraints = false
    box.contentView = inner
    NSLayoutConstraint.activate([
        box.widthAnchor.constraint(equalToConstant: cardWidth),
        inner.leadingAnchor.constraint(equalTo: box.leadingAnchor),
        inner.trailingAnchor.constraint(equalTo: box.trailingAnchor),
        inner.topAnchor.constraint(equalTo: box.topAnchor),
        inner.bottomAnchor.constraint(equalTo: box.bottomAnchor),
    ])

    let header = row([symbolView(symbol, size: 11, color: .secondaryLabelColor),
                      label(title.uppercased(), size: 11, weight: .semibold, color: .secondaryLabelColor),
                      spring()], spacing: 5, width: cardWidth)

    let wrapper = NSStackView(views: [header, box])
    wrapper.orientation = .vertical
    wrapper.alignment = .leading
    wrapper.spacing = 6
    wrapper.translatesAutoresizingMaskIntoConstraints = false
    return wrapper
}

// MARK: - Window

final class SettingsWindow: NSWindowController, NSWindowDelegate {
    private unowned let app: AppDelegate


    private let macIcon = NSImageView()
    private let macLabel = label("")
    private let macButton = NSButton()

    private let upNextStack = NSStackView()
    private let calendarStack = NSStackView()

    private let styleControl = NSSegmentedControl(labels: AlertStyle.allCases.map(\.title),
                                                  trackingMode: .selectOne, target: nil, action: nil)
    private let styleDetail = label("", size: 11, color: .tertiaryLabelColor)
    private let leadControl = NSSegmentedControl(labels: ["1 min", "2 min", "5 min", "10 min"],
                                                 trackingMode: .selectOne, target: nil, action: nil)
    private let dismissControl = NSSegmentedControl(labels: ["Never", "30s", "60s", "150s"],
                                                    trackingMode: .selectOne, target: nil, action: nil)
    private let snoozeSwitch = NSSwitch()
    private let linkOnlySwitch = NSSwitch()
    private let soundSwitch = NSSwitch()
    private let loginSwitch = NSSwitch()
    private let installButton = NSButton()

    private var poll: Timer?

    init(app: AppDelegate) {
        self.app = app
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "MeetingNudge"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 420)
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = buildBody()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    private func buildBody() -> NSView {
        let appIcon = symbolView("calendar.badge.clock", size: 30, color: .controlAccentColor)
        let titles = NSStackView(views: [
            label("MeetingNudge", size: 19, weight: .bold),
            label("Never miss the first minute of a meeting.", size: 12, color: .secondaryLabelColor),
        ])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 1
        let header = row([appIcon, titles, spring()], spacing: 12, width: cardWidth)

        // Calendar access
        macButton.bezelStyle = .rounded
        macButton.controlSize = .small
        macButton.target = self
        macButton.action = #selector(macTapped)
        let macCard = card("Calendars", symbol: "calendar.badge.exclamationmark", rows: [
            row([macIcon, macLabel, spring(), macButton]),
            wrapping("Reads the calendar database Calendar.app uses, which covers iCloud, Exchange, "
                     + "local calendars, and any Google or Exchange account you added in System "
                     + "Settings › Internet Accounts. MeetingNudge stores no credentials of its own "
                     + "and makes no network requests."),
        ])

        // Up next
        upNextStack.orientation = .vertical
        upNextStack.alignment = .leading
        upNextStack.spacing = 5
        upNextStack.translatesAutoresizingMaskIntoConstraints = false
        upNextStack.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
        let upNextCard = card("Up next", symbol: "clock", rows: [upNextStack])

        // Calendars
        calendarStack.orientation = .vertical
        calendarStack.alignment = .leading
        calendarStack.spacing = 2
        calendarStack.translatesAutoresizingMaskIntoConstraints = false
        calendarStack.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
        let calendarCard = card("Alert me about", symbol: "calendar", rows: [calendarStack])

        // Alerts
        styleControl.target = self
        styleControl.action = #selector(styleChanged)
        styleControl.segmentDistribution = .fillEqually
        leadControl.target = self
        leadControl.action = #selector(leadChanged)
        leadControl.segmentDistribution = .fillEqually
        dismissControl.target = self
        dismissControl.action = #selector(dismissChanged)
        dismissControl.segmentDistribution = .fillEqually
        snoozeSwitch.target = self
        snoozeSwitch.action = #selector(snoozeToggled)
        linkOnlySwitch.target = self
        linkOnlySwitch.action = #selector(linkOnlyToggled)
        soundSwitch.target = self
        soundSwitch.action = #selector(soundToggled)

        let alertCard = card("Alert", symbol: "bell", rows: [
            row([label("Style"), spring(), styleControl]),
            styleDetail,
            separator(),
            row([label("Warn me"), spring(), leadControl]),
            row([label("Clear itself after"), spring(), dismissControl]),
            separator(),
            row([label("Show a remind-at-start button"), spring(), snoozeSwitch]),
            row([label("Only meetings with a join link"), spring(), linkOnlySwitch]),
            row([label("Play a sound"), spring(), soundSwitch]),
        ])

        // Startup
        loginSwitch.target = self
        loginSwitch.action = #selector(loginToggled)
        installButton.title = "Move to Applications"
        installButton.bezelStyle = .rounded
        installButton.controlSize = .small
        installButton.target = self
        installButton.action = #selector(installTapped)
        let startupCard = card("Startup", symbol: "power", rows: [
            row([label("Launch at login"), spring(), loginSwitch]),
            row([label("Tip: keep the app in Applications.", size: 11, color: .tertiaryLabelColor),
                 spring(), installButton]),
        ])

        // Footer
        let preview = NSButton(title: "Preview an alert", target: self, action: #selector(previewTapped))
        preview.bezelStyle = .rounded
        let logs = NSButton(title: "Open log", target: self, action: #selector(openLog))
        logs.bezelStyle = .rounded
        logs.controlSize = .small
        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .rounded
        let footer = row([preview, logs, spring(), quit], width: cardWidth)

        let root = NSStackView(views: [header, macCard, upNextCard,
                                       calendarCard, alertCard, startupCard, footer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 34, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false

        // The whole page scrolls, so adding a setting never pushes the footer
        // off the bottom of the window.
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.contentView = FlippedClipView()
        scroll.documentView = root
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            root.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            root.widthAnchor.constraint(equalToConstant: 520),
        ])
        return scroll
    }

    // MARK: State

    private func setStatus(_ view: NSImageView, _ symbol: String, _ color: NSColor) {
        view.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        view.contentTintColor = color
    }

    func refresh() {
        refreshMac()
        refreshUpNext()
        refreshCalendars()

        styleControl.selectedSegment = AlertStyle.allCases.firstIndex(of: Prefs.alertStyle) ?? 0
        styleDetail.stringValue = Prefs.alertStyle.detail
        leadControl.selectedSegment = Prefs.leadChoices.firstIndex(of: Prefs.leadTime) ?? 0
        dismissControl.selectedSegment = Prefs.autoDismissChoices.firstIndex(of: Prefs.autoDismiss) ?? 3
        snoozeSwitch.state = Prefs.snoozeEnabled ? .on : .off
        linkOnlySwitch.state = Prefs.onlyWithJoinLink ? .on : .off
        soundSwitch.state = Prefs.playSound ? .on : .off

        let installed = Bundle.main.bundlePath.hasPrefix("/Applications/")
        loginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginSwitch.isEnabled = true
        installButton.superview?.isHidden = installed
    }

    private func refreshMac() {
        switch app.eventKit.authorizationStatus {
        case .fullAccess:
            setStatus(macIcon, "checkmark.circle.fill", .systemGreen)
            macLabel.stringValue = "Calendar access granted"
            macButton.isHidden = true
        case .denied, .restricted, .writeOnly:
            setStatus(macIcon, "xmark.circle.fill", .systemRed)
            macLabel.stringValue = "Calendar access is turned off"
            macButton.title = "Open Privacy Settings…"
            macButton.isHidden = false
        default:
            setStatus(macIcon, "questionmark.circle.fill", .systemOrange)
            macLabel.stringValue = "Calendar access not granted"
            macButton.title = "Allow access"
            macButton.isHidden = false
        }
    }

    private func refreshUpNext() {
        upNextStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let now = Date()
        let soon = app.meetings.filter { $0.start > now.addingTimeInterval(-60) }.prefix(4)
        guard !soon.isEmpty else {
            upNextStack.addArrangedSubview(
                label("Nothing scheduled in the next 14 hours.", size: 12, color: .tertiaryLabelColor))
            return
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE HH:mm"
        for meeting in soon {
            let minutes = Int(meeting.start.timeIntervalSince(now) / 60)
            let when = minutes < 60 ? "in \(max(0, minutes)) min" : fmt.string(from: meeting.start)
            let hasLink = meeting.joinURL != nil
            let icon = symbolView(hasLink ? "video.fill" : "video.slash", size: 11,
                                  color: hasLink ? .systemGreen : .tertiaryLabelColor)
            icon.toolTip = meeting.joinURL?.absoluteString ?? "No join link in this event"
            upNextStack.addArrangedSubview(
                row([icon, label(meeting.title, size: 12), spring(),
                     label(when, size: 11, color: .secondaryLabelColor)]))
        }
    }

    private func calendarRow(_ calendar: SourceCalendar, muted: Bool) -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = (colorFromHex(calendar.colorHex) ?? .systemGray).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 10).isActive = true

        let toggle = NSSwitch()
        toggle.controlSize = .mini
        toggle.state = muted ? .off : .on
        toggle.target = self
        toggle.action = #selector(calendarToggled(_:))
        toggle.identifier = NSUserInterfaceItemIdentifier(calendar.id)

        return row([dot, label(calendar.title), spring(), toggle], width: rowWidth - 10)
    }

    private func refreshCalendars() {
        calendarStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let all = app.eventKit.calendars
        guard !all.isEmpty else {
            calendarStack.addArrangedSubview(
                label("Grant calendar access above to pick calendars.", size: 12, color: .tertiaryLabelColor))
            return
        }
        let muted = Prefs.mutedCalendars
        let grouped = Dictionary(grouping: all) { $0.accountTitle }
        for key in grouped.keys.sorted() {
            let head = label(key, size: 10, weight: .semibold, color: .tertiaryLabelColor)
            let wrap = NSStackView(views: [head])
            wrap.orientation = .horizontal
            wrap.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 2, right: 0)
            calendarStack.addArrangedSubview(wrap)
            for calendar in (grouped[key] ?? []).sorted(by: { $0.title < $1.title }) {
                calendarStack.addArrangedSubview(calendarRow(calendar, muted: muted.contains(calendar.id)))
            }
        }
    }

    // MARK: Actions





    @objc private func macTapped() {
        if app.eventKit.authorizationStatus == .notDetermined {
            app.eventKit.requestAccess { [weak self] _ in
                self?.app.refresh()
                self?.refresh()
            }
        } else {
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
        }
    }


    @objc private func calendarToggled(_ sender: NSSwitch) {
        guard let id = sender.identifier?.rawValue else { return }
        var muted = Prefs.mutedCalendars
        if sender.state == .on { muted.remove(id) } else { muted.insert(id) }
        Prefs.mutedCalendars = muted
        app.refresh()
        refreshUpNext()
    }

    @objc private func styleChanged() {
        Prefs.alertStyle = AlertStyle.allCases[max(0, styleControl.selectedSegment)]
        styleDetail.stringValue = Prefs.alertStyle.detail
        if Prefs.alertStyle == .notification { app.requestNotificationAccess() }
    }

    @objc private func leadChanged() {
        Prefs.leadTime = Prefs.leadChoices[max(0, leadControl.selectedSegment)]
    }

    @objc private func dismissChanged() {
        Prefs.autoDismiss = Prefs.autoDismissChoices[max(0, dismissControl.selectedSegment)]
    }

    @objc private func snoozeToggled() { Prefs.snoozeEnabled = snoozeSwitch.state == .on }
    @objc private func linkOnlyToggled() {
        Prefs.onlyWithJoinLink = linkOnlySwitch.state == .on
        app.refresh()
        refreshUpNext()
    }
    @objc private func soundToggled() { Prefs.playSound = soundSwitch.state == .on }

    @objc private func loginToggled() {
        let turningOn = loginSwitch.state == .on
        do {
            if turningOn { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            let alert = NSAlert()
            alert.messageText = turningOn ? "Could not turn on launch at login"
                                          : "Could not turn off launch at login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            refresh()
            return
        }
        if turningOn, SMAppService.mainApp.status == .requiresApproval {
            let alert = NSAlert()
            alert.messageText = "One more step"
            alert.informativeText = "macOS needs you to allow MeetingNudge in Login Items."
            alert.addButton(withTitle: "Open Login Items")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
            }
        }
        refresh()
    }

    /// Copy into /Applications and restart from there, so the login item does
    /// not point at a build folder that may get deleted.
    @objc private func installTapped() {
        let destination = URL(fileURLWithPath: "/Applications/MeetingNudge.app")
        let confirm = NSAlert()
        confirm.messageText = "Move MeetingNudge to Applications?"
        confirm.informativeText = "It will be copied to \(destination.path) and restarted from there."
        confirm.addButton(withTitle: "Move and restart")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: Bundle.main.bundleURL, to: destination)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not move MeetingNudge"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    @objc private func previewTapped() { app.previewAlert() }

    @objc private func openLog() {
        guard let url = Log.url else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            Log.write("log opened from settings")
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: Window

    func show() {
        Prefs.didOnboard = true
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        refresh()
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func windowWillClose(_ notification: Notification) {
        poll?.invalidate()
        poll = nil
    }
}
