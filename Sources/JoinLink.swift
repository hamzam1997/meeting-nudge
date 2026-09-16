import Foundation

/// Known conferencing providers, most specific first. Only used when a
/// provider did not hand us a structured conference link.
private let providerPatterns = [
    #"https://[\w.-]*zoom\.us/[js]/[^\s<>"')]+"#,
    #"https://meet\.google\.com/[a-z]{3,}-[a-z]{3,}-[a-z]{3,}"#,
    #"https://teams\.microsoft\.com/l/meetup-join/[^\s<>"')]+"#,
    #"https://teams\.live\.com/meet/[^\s<>"')]+"#,
    #"https://[\w.-]*webex\.com/[^\s<>"')]+"#,
    #"https://meet\.jit\.si/[^\s<>"')]+"#,
    #"https://[\w.-]*whereby\.com/[^\s<>"')]+"#,
    #"https://[\w.-]*gotomeeting\.com/[^\s<>"')]+"#,
    #"https://[\w.-]*bluejeans\.com/[^\s<>"')]+"#,
    #"https://[\w.-]*chime\.aws/[^\s<>"')]+"#,
    #"https://app\.slack\.com/huddle/[^\s<>"')]+"#,
    #"https://[\w.-]*around\.co/[^\s<>"')]+"#,
]

private func firstMatch(_ pattern: String, in text: String) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = re.firstMatch(in: text, range: range),
          let found = Range(match.range, in: text) else { return nil }
    // Trim punctuation that commonly trails a URL in prose or HTML notes.
    return String(text[found]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)>]\"'"))
}

/// Best guess at the "click this to be in the meeting" link, given the three
/// places a calendar event can hide one.
func bestJoinURL(url: String?, location: String?, notes: String?) -> URL? {
    let haystacks = [url, location, notes].compactMap { $0 }
    for pattern in providerPatterns {
        for text in haystacks {
            if let hit = firstMatch(pattern, in: text), let parsed = URL(string: hit) { return parsed }
        }
    }
    if let raw = url, raw.hasPrefix("http"), let parsed = URL(string: raw) { return parsed }
    for text in haystacks {
        if let hit = firstMatch(#"https?://[^\s<>"')]+"#, in: text), let parsed = URL(string: hit) { return parsed }
    }
    return nil
}

/// Human name for the service a join link points at, for the alert's button.
func providerName(for url: URL) -> String? {
    guard let host = url.host?.lowercased() else { return nil }
    let names: [(String, String)] = [
        ("zoom.us", "Zoom"),
        ("meet.google.com", "Google Meet"),
        ("teams.microsoft.com", "Teams"),
        ("teams.live.com", "Teams"),
        ("webex.com", "Webex"),
        ("meet.jit.si", "Jitsi"),
        ("whereby.com", "Whereby"),
        ("gotomeeting.com", "GoToMeeting"),
        ("bluejeans.com", "BlueJeans"),
        ("chime.aws", "Chime"),
        ("slack.com", "Slack"),
    ]
    return names.first { host == $0.0 || host.hasSuffix("." + $0.0) }?.1
}
