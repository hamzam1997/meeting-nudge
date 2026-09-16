import AppKit
import UserNotifications

/// Borderless panel that floats above everything, including full screen apps,
/// without stealing keyboard focus from whatever you were doing.
final class NudgePanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

private func bigButton(_ title: String, accent: Bool, height: CGFloat,
                       target: AnyObject, action: Selector) -> NSButton {
    let button = NSButton(title: title, target: target, action: action)
    button.isBordered = false
    button.wantsLayer = true
    button.layer?.cornerRadius = height > 40 ? 12 : 8
    button.layer?.backgroundColor = (accent ? NSColor.controlAccentColor
                                            : NSColor.white.withAlphaComponent(0.14)).cgColor
    button.attributedTitle = NSAttributedString(string: title, attributes: [
        .font: NSFont.systemFont(ofSize: height > 40 ? 17 : 13, weight: .semibold),
        .foregroundColor: accent ? NSColor.white : NSColor.labelColor,
    ])
    return button
}

/// One meeting alert on screen. Full screen covers every display and blocks
/// clicks; banner is a corner panel that leaves the rest of the screen alone.
final class Nudge {
    private var panels: [NSPanel] = []
    private var badges: [NSTextField] = []
    private var ticker: Timer?
    private var autoClose: Timer?

    private let meeting: Meeting
    private let style: AlertStyle
    private let onJoin: (Meeting) -> Void
    private let onSnooze: (Meeting) -> Void
    private let onClose: () -> Void

    init(meeting: Meeting, style: AlertStyle,
         onJoin: @escaping (Meeting) -> Void,
         onSnooze: @escaping (Meeting) -> Void,
         onClose: @escaping () -> Void) {
        self.meeting = meeting
        self.style = style == .notification ? .banner : style
        self.onJoin = onJoin
        self.onSnooze = onSnooze
        self.onClose = onClose

        let screens = self.style == .fullScreen ? NSScreen.screens
            : [NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main].compactMap { $0 }

        for screen in screens {
            panels.append(self.style == .fullScreen ? fullScreenPanel(on: screen) : bannerPanel(on: screen))
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            panels.forEach { $0.animator().alphaValue = 1 }
        }
        if Prefs.playSound {
            NSSound(named: self.style == .fullScreen ? "Submarine" : "Ping")?.play()
        }

        updateBadges()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateBadges() }
        let dismissAfter = Prefs.autoDismiss
        if dismissAfter > 0 {
            autoClose = Timer.scheduledTimer(withTimeInterval: dismissAfter, repeats: false) { [weak self] _ in
                self?.close()
            }
        }
    }

    // MARK: Panels

    private func basePanel(frame: NSRect) -> NSPanel {
        let panel = NudgePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.alphaValue = 0
        return panel
    }

    private func fullScreenPanel(on screen: NSScreen) -> NSPanel {
        let panel = basePanel(frame: screen.frame)
        panel.hasShadow = false

        let bounds = NSRect(origin: .zero, size: screen.frame.size)
        let blur = NSVisualEffectView(frame: bounds)
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]

        let scrim = NSView(frame: bounds)
        scrim.wantsLayer = true
        scrim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        scrim.autoresizingMask = [.width, .height]
        blur.addSubview(scrim)
        blur.addSubview(card(width: 660, big: true, in: bounds))

        panel.contentView = blur
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        return panel
    }

    private func bannerPanel(on screen: NSScreen) -> NSPanel {
        let size = NSSize(width: 420, height: 0)
        let panel = basePanel(frame: NSRect(origin: .zero, size: NSSize(width: size.width, height: 160)))
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true

        let host = NSView(frame: NSRect(origin: .zero, size: NSSize(width: size.width, height: 160)))
        let body = card(width: size.width, big: false, in: host.bounds)
        host.frame = NSRect(origin: .zero, size: body.frame.size)
        body.setFrameOrigin(.zero)
        host.addSubview(body)

        panel.setContentSize(body.frame.size)
        panel.contentView = host
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.maxX - body.frame.width - 20,
                                     y: visible.maxY - body.frame.height - 20))
        panel.orderFrontRegardless()
        return panel
    }

    /// The card itself, sized to its own content so a one or two line title
    /// both look deliberate.
    private func card(width: CGFloat, big: Bool, in bounds: NSRect) -> NSView {
        let inset: CGFloat = big ? 40 : 20
        let textWidth = width - inset * 2

        let titleLabel = NSTextField(wrappingLabelWithString: meeting.title)
        titleLabel.font = .systemFont(ofSize: big ? 38 : 19, weight: .bold)
        titleLabel.alignment = big ? .center : .left
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isSelectable = false
        let titleHeight = min(big ? 96 : 52, ceil(titleLabel.sizeThatFits(
            NSSize(width: textWidth, height: .greatestFiniteMagnitude)).height))

        let buttonHeight: CGFloat = big ? 54 : 34
        let buttonY: CGFloat = big ? 40 : 18
        let subY = buttonY + buttonHeight + (big ? 34 : 18)
        let titleY = subY + 24 + (big ? 18 : 8)
        let badgeY = titleY + titleHeight + (big ? 18 : 8)
        let height = badgeY + 22 + (big ? 36 : 18)

        let card = NSVisualEffectView(frame: NSRect(x: (bounds.width - width) / 2,
                                                    y: (bounds.height - height) / 2,
                                                    width: width, height: height))
        card.material = .hudWindow
        card.blendingMode = big ? .withinWindow : .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = big ? 24 : 16
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        card.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]

        let badge = NSTextField(labelWithString: "")
        badge.font = .systemFont(ofSize: big ? 15 : 11, weight: .bold)
        badge.textColor = colorFromHex(meeting.colorHex) ?? .controlAccentColor
        badge.alignment = big ? .center : .left
        badge.frame = NSRect(x: inset, y: badgeY, width: textWidth, height: 22)
        card.addSubview(badge)
        badges.append(badge)

        titleLabel.frame = NSRect(x: inset, y: titleY, width: textWidth, height: titleHeight)
        card.addSubview(titleLabel)

        let subLabel = NSTextField(labelWithString: subtitle())
        subLabel.font = .systemFont(ofSize: big ? 17 : 12)
        subLabel.textColor = .secondaryLabelColor
        subLabel.alignment = big ? .center : .left
        subLabel.lineBreakMode = .byTruncatingTail
        subLabel.frame = NSRect(x: inset, y: subY, width: textWidth, height: 24)
        card.addSubview(subLabel)

        var titles: [(String, Bool, Selector)] = []
        if let url = meeting.joinURL {
            titles.append((providerName(for: url).map { "Join " + $0 } ?? "Join now", true, #selector(joinTapped)))
        } else {
            titles.append(("Open Calendar", true, #selector(joinTapped)))
        }
        if Prefs.snoozeEnabled, meeting.start.timeIntervalSinceNow > 5 {
            titles.append(("At start time", false, #selector(snoozeTapped)))
        }
        titles.append(("Dismiss", false, #selector(dismissTapped)))

        let font = NSFont.systemFont(ofSize: big ? 17 : 13, weight: .semibold)
        let gap: CGFloat = big ? 16 : 10
        let widths = titles.map { title in
            max(big ? 150 : 90, ceil(NSAttributedString(string: title.0, attributes: [.font: font])
                .size().width) + (big ? 56 : 28))
        }
        let total = widths.reduce(0, +) + gap * CGFloat(titles.count - 1)
        var x = big ? (width - total) / 2 : inset
        for (index, spec) in titles.enumerated() {
            let button = bigButton(spec.0, accent: spec.1, height: buttonHeight,
                                   target: self, action: spec.2)
            button.frame = NSRect(x: x, y: buttonY, width: widths[index], height: buttonHeight)
            card.addSubview(button)
            x += widths[index] + gap
        }

        return card
    }

    private func subtitle() -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        var parts = [fmt.string(from: meeting.start)]
        if let end = meeting.end { parts[0] += " – " + fmt.string(from: end) }
        if let place = meeting.location?.trimmingCharacters(in: .whitespacesAndNewlines),
           !place.isEmpty, !place.lowercased().hasPrefix("http") {
            parts.append(place)
        } else {
            parts.append(meeting.calendarTitle)
        }
        return parts.joined(separator: "  ·  ")
    }

    private func updateBadges() {
        let remaining = Int(meeting.start.timeIntervalSinceNow.rounded())
        let text: String
        if remaining <= 0 {
            let late = -remaining
            text = late < 60 ? "STARTING NOW" : "STARTED \(late / 60) MIN AGO"
        } else {
            text = String(format: "STARTS IN %d:%02d", remaining / 60, remaining % 60)
        }
        badges.forEach { $0.stringValue = text }
    }

    @objc private func joinTapped() {
        onJoin(meeting)
        close()
    }

    @objc private func snoozeTapped() {
        onSnooze(meeting)
        close()
    }

    @objc private func dismissTapped() { close() }

    func close() {
        ticker?.invalidate()
        autoClose?.invalidate()
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        badges.removeAll()
        onClose()
    }
}

// MARK: - Notification style

/// The quiet option: a normal macOS notification carrying a Join button.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let category = "MEETING_NUDGE"
    private var links: [String: URL] = [:]
    var onJoin: ((URL) -> Void)?

    func prepare() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let join = UNNotificationAction(identifier: "JOIN", title: "Join", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [join],
                                   intentIdentifiers: [], options: [])
        ])
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            Log.write("notification authorization granted=\(granted) error=\(error?.localizedDescription ?? "none")")
        }
    }

    func post(_ meeting: Meeting) {
        let content = UNMutableNotificationContent()
        content.title = meeting.title
        let minutes = max(0, Int((meeting.start.timeIntervalSinceNow / 60).rounded()))
        content.body = minutes <= 0 ? "Starting now" : "Starts in \(minutes) min"
        content.sound = Prefs.playSound ? .default : nil
        if let url = meeting.joinURL {
            content.categoryIdentifier = category
            links[meeting.occurrenceID] = url
        }
        let request = UNNotificationRequest(identifier: meeting.occurrenceID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void) {
        if let url = links[response.notification.request.identifier] {
            onJoin?(url)
        }
        completion()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .sound])
    }
}
