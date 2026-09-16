import Foundation

/// One calendar the app can watch, grouped under an account.
struct SourceCalendar: Equatable {
    let id: String
    let title: String
    let accountTitle: String
    /// CSS hex like "#039be5". Kept as a string so this model stays free of
    /// AppKit and can be tested on its own.
    let colorHex: String?
}

/// A meeting, normalised out of EventKit.
struct Meeting {
    /// The iCalUID. Two calendars carrying the same invitation share it, which
    /// is what makes de-duplication possible.
    let externalID: String?
    let title: String
    let start: Date
    let end: Date?
    let location: String?
    let notes: String?
    let urlString: String?
    let isAllDay: Bool
    let declined: Bool
    let isCancelled: Bool
    let calendarID: String
    let calendarTitle: String
    let accountTitle: String
    let colorHex: String?

    /// Wherever the invitation hid the join link.
    var joinURL: URL? {
        bestJoinURL(url: urlString, location: location, notes: notes)
    }

    /// Stable per occurrence, so each instance of a repeating meeting alerts
    /// once and tomorrow's standup is not mistaken for today's.
    var occurrenceID: String {
        occurrenceKey(identifier: externalID, title: title, start: start)
    }

    /// Meetings nobody should be interrupted for.
    var isAlertable: Bool {
        !isAllDay && !declined && !isCancelled
    }
}

/// Collapse the same invitation appearing on more than one calendar.
///
/// This happens more than you would expect: a shared team calendar and your
/// own copy of the same invitation, or one account subscribed to another. The
/// richer record wins, meaning the one that actually has a join link.
func dedupeMeetings(_ meetings: [Meeting]) -> [Meeting] {
    var byKey: [String: Meeting] = [:]
    var order: [String] = []

    for meeting in meetings {
        let key = meeting.externalID.map { $0 + "@" + String(Int(meeting.start.timeIntervalSince1970)) }
            ?? meeting.occurrenceID
        if let existing = byKey[key] {
            if existing.joinURL == nil, meeting.joinURL != nil { byKey[key] = meeting }
        } else {
            byKey[key] = meeting
            order.append(key)
        }
    }

    return order.compactMap { byKey[$0] }.sorted { $0.start < $1.start }
}
