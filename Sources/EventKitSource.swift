import AppKit
import EventKit

/// Meetings from the calendar database macOS already keeps.
///
/// This covers iCloud, Exchange, local calendars, and any Google account
/// connected through System Settings. It is the app's only source, which is
/// why the app needs no network access and no credential storage of its own:
/// macOS holds the account tokens and syncs them.
final class EventKitSource {
    private let store = EKEventStore()

    private(set) var meetings: [Meeting] = []

    /// Read the live authorization status rather than caching a flag. Caching
    /// it introduced a startup race where the first refresh was skipped even
    /// though permission had been granted.
    var isConnected: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    var calendars: [SourceCalendar] {
        guard isConnected else { return [] }
        return store.calendars(for: .event).map { calendar in
            SourceCalendar(id: calendar.calendarIdentifier,
                           title: calendar.title,
                           accountTitle: calendar.source?.title ?? "On My Mac",
                           colorHex: calendar.color.map(hexString))
        }.sorted { ($0.accountTitle, $0.title) < ($1.accountTitle, $1.title) }
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        store.requestFullAccessToEvents { granted, error in
            Log.write("EventKit access granted=\(granted) error=\(error?.localizedDescription ?? "none")")
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func observeChanges(_ handler: @escaping () -> Void) {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged,
                                               object: store, queue: .main) { _ in handler() }
    }

    func refresh(muted: Set<String>) {
        guard isConnected else {
            meetings = []
            return
        }
        let active = store.calendars(for: .event).filter { !muted.contains($0.calendarIdentifier) }
        guard !active.isEmpty else {
            meetings = []
            return
        }
        let predicate = store.predicateForEvents(
            withStart: Date().addingTimeInterval(-lookbehindWindow),
            end: Date().addingTimeInterval(lookaheadWindow),
            calendars: active)

        meetings = store.events(matching: predicate).compactMap { event -> Meeting? in
            // startDate is an implicitly unwrapped optional in EventKit. An
            // event without one cannot be scheduled against, and unwrapping it
            // blindly would take the whole agent down.
            guard let start = event.startDate as Date? else { return nil }
            let me = event.attendees?.first { $0.isCurrentUser }
            return Meeting(
                externalID: event.calendarItemExternalIdentifier,
                title: event.title ?? "Meeting",
                start: start,
                end: event.endDate as Date?,
                location: event.location,
                notes: event.notes,
                urlString: event.url?.absoluteString,
                isAllDay: event.isAllDay,
                declined: me?.participantStatus == .declined,
                isCancelled: event.status == .canceled,
                calendarID: event.calendar?.calendarIdentifier ?? "",
                calendarTitle: event.calendar?.title ?? "",
                accountTitle: event.calendar?.source?.title ?? "On My Mac",
                colorHex: event.calendar?.color.map(hexString))
        }
    }
}

/// CSS hex for a calendar colour, so the model layer stays free of AppKit.
func hexString(_ color: NSColor) -> String {
    let rgb = color.usingColorSpace(.sRGB) ?? color
    let r = Int((rgb.redComponent * 255).rounded())
    let g = Int((rgb.greenComponent * 255).rounded())
    let b = Int((rgb.blueComponent * 255).rounded())
    return String(format: "#%02x%02x%02x", r, g, b)
}

/// The reverse, for colours that arrived from the Google API.
func colorFromHex(_ hex: String?) -> NSColor? {
    guard var text = hex else { return nil }
    if text.hasPrefix("#") { text.removeFirst() }
    guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
    return NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255,
                   green: CGFloat((value >> 8) & 0xff) / 255,
                   blue: CGFloat(value & 0xff) / 255, alpha: 1)
}
