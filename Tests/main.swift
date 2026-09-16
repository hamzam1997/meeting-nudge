import Foundation

var passed = 0
func check(_ condition: Bool, _ what: String) {
    assert(condition, "FAILED: \(what)")
    passed += 1
    print("ok  \(what)")
}
func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ what: String) {
    assert(actual == expected, "FAILED: \(what)\n  expected: \(expected)\n  actual:   \(actual)")
    passed += 1
    print("ok  \(what)")
}

// MARK: - Alert timing, which everything else hangs off

let noon = Date(timeIntervalSince1970: 1_700_000_000)
func at(_ offset: TimeInterval) -> Date { noon.addingTimeInterval(offset) }

check(!shouldAlert(start: noon, now: at(-120), leadTime: 60), "two minutes out is early for a one minute lead")
check(shouldAlert(start: noon, now: at(-60), leadTime: 60), "fires exactly at the lead time")
check(shouldAlert(start: noon, now: at(-5), leadTime: 60), "still fires just before the start")
check(shouldAlert(start: noon, now: noon, leadTime: 60), "fires at the start itself")
check(shouldAlert(start: noon, now: at(20), leadTime: 60), "a late tick inside the grace window still fires")
check(!shouldAlert(start: noon, now: at(45), leadTime: 60), "past the grace window it is a missed meeting")
check(shouldAlert(start: noon, now: at(-240), leadTime: 300), "a longer lead time fires earlier")

checkEqual(occurrenceKey(identifier: "abc", title: "Standup", start: noon),
           occurrenceKey(identifier: "abc", title: "Standup", start: noon),
           "the same occurrence has a stable key")
check(occurrenceKey(identifier: "abc", title: "Standup", start: noon)
      != occurrenceKey(identifier: "abc", title: "Standup", start: at(86400)),
      "tomorrow's standup is a different occurrence")

// MARK: - Join links

checkEqual(bestJoinURL(url: "https://wiki.corp/agenda", location: nil,
                       notes: "Agenda: https://wiki.corp/agenda\nJoin: https://acme.zoom.us/j/98765?pwd=x")?.absoluteString,
           "https://acme.zoom.us/j/98765?pwd=x", "a zoom link beats an unrelated url field")
checkEqual(bestJoinURL(url: nil, location: "https://meet.google.com/abc-defg-hij", notes: nil)?.absoluteString,
           "https://meet.google.com/abc-defg-hij", "google meet in the location field")
checkEqual(bestJoinURL(url: nil, location: nil,
                       notes: "<a href=\"https://teams.microsoft.com/l/meetup-join/19%3ameeting_X\">Join</a>")?.absoluteString,
           "https://teams.microsoft.com/l/meetup-join/19%3ameeting_X", "teams link inside html notes")
checkEqual(bestJoinURL(url: nil, location: nil, notes: "Dial in at https://meet.jit.si/standup, see you there.")?.absoluteString,
           "https://meet.jit.si/standup", "trailing prose punctuation is stripped")
checkEqual(bestJoinURL(url: "https://example.com/room/42", location: "Room 3", notes: nil)?.absoluteString,
           "https://example.com/room/42", "falls back to the url field")
check(bestJoinURL(url: nil, location: "Meeting Room 4B", notes: "Bring the deck") == nil,
      "an in-person meeting has nothing to join")

checkEqual(providerName(for: URL(string: "https://acme.zoom.us/j/1")!), "Zoom", "zoom subdomain named")
checkEqual(providerName(for: URL(string: "https://meet.google.com/a-b-c")!), "Google Meet", "meet named")
check(providerName(for: URL(string: "https://notzoom.us.evil.com/j/1")!) == nil, "a lookalike host is not zoom")
check(providerName(for: URL(string: "https://wiki.corp/x")!) == nil, "unknown host has no provider name")

// MARK: - De-duplicating the same invitation on two calendars

func sample(_ uid: String, link: String?, title: String = "Standup",
            start: Date = noon) -> Meeting {
    Meeting(externalID: uid, title: title, start: start, end: nil, location: nil,
            notes: link, urlString: nil, isAllDay: false, declined: false,
            isCancelled: false, calendarID: "c", calendarTitle: "c",
            accountTitle: "a", colorHex: nil)
}

let deduped = dedupeMeetings([
    sample("uid-a", link: nil),
    sample("uid-a", link: "Join https://meet.google.com/a-b-c"),
])
checkEqual(deduped.count, 1, "the same invitation on two calendars appears once")
checkEqual(deduped[0].joinURL?.absoluteString, "https://meet.google.com/a-b-c",
           "the copy that carries a join link wins")

let dedupedKeepFirst = dedupeMeetings([
    sample("uid-b", link: "Join https://acme.zoom.us/j/9"),
    sample("uid-b", link: nil),
])
checkEqual(dedupedKeepFirst[0].joinURL?.absoluteString, "https://acme.zoom.us/j/9",
           "a link already found is not thrown away for a blank copy")

let sorted = dedupeMeetings([
    sample("uid-c", link: nil, start: at(600)),
    sample("uid-d", link: nil, start: noon),
])
checkEqual(sorted.map(\.externalID), ["uid-d", "uid-c"], "the list comes back sorted by start")

let recurring = dedupeMeetings([
    sample("uid-e", link: nil, start: noon),
    sample("uid-e", link: nil, start: at(86400)),
])
checkEqual(recurring.count, 2, "two occurrences of one recurring meeting both survive")

// Meetings nobody should be interrupted for.
func flagged(allDay: Bool = false, declined: Bool = false, cancelled: Bool = false) -> Meeting {
    Meeting(externalID: "x", title: "x", start: noon, end: nil, location: nil, notes: nil,
            urlString: nil, isAllDay: allDay, declined: declined, isCancelled: cancelled,
            calendarID: "c", calendarTitle: "c", accountTitle: "a", colorHex: nil)
}
check(flagged().isAlertable, "an ordinary meeting is alertable")
check(!flagged(allDay: true).isAlertable, "all day events are not alertable")
check(!flagged(declined: true).isAlertable, "declined meetings are not alertable")
check(!flagged(cancelled: true).isAlertable, "cancelled meetings are not alertable")

print("\n\(passed) checks passed")
