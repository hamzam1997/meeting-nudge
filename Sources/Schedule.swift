import Foundation

/// Whether a meeting starting at `start` should raise its alert right now.
///
/// The window opens `leadTime` before the meeting and stays open briefly after
/// it starts, so a tick that lands late still fires instead of silently
/// skipping the meeting. A late tick happens more often than you would think:
/// a slow wake from sleep, or a coalesced timer. Anything older than `grace`
/// counts as already missed.
func shouldAlert(start: Date, now: Date, leadTime: TimeInterval, grace: TimeInterval = 30) -> Bool {
    let delta = start.timeIntervalSince(now)
    return delta <= leadTime && delta > -grace
}

/// Identifies one occurrence of a repeating event, so each instance alerts
/// once and tomorrow's standup is not mistaken for today's.
func occurrenceKey(identifier: String?, title: String?, start: Date) -> String {
    (identifier ?? title ?? "meeting") + "@" + String(Int(start.timeIntervalSince1970))
}

/// How far ahead the providers should look. Long enough to show an "up next"
/// list, short enough that a poll stays cheap.
let lookaheadWindow: TimeInterval = 14 * 3600

/// Events that ended more than this long ago are of no interest.
let lookbehindWindow: TimeInterval = 3600
