# MeetingNudge

A macOS menu bar app that takes over your screen one minute before a meeting
starts, and gives you one button to join it.

No dock icon, and no notification you will swipe away by reflex. The default
alert dims every display, counts down, and waits for you to either join or
dismiss. If that is too much, it can be a corner banner or an ordinary
notification instead.

## Install

```bash
git clone https://github.com/hamzam1997/meeting-nudge.git
cd meeting-nudge
./build.sh
open build/MeetingNudge.app
```

Requires macOS 14 or later. Swift comes with the Xcode command line tools,
which you get from `xcode-select --install`. There is no Xcode project and no
third-party dependencies.

On first launch macOS asks for calendar access and the settings window opens.

## What it can and cannot reach

MeetingNudge reads the local calendar database through EventKit and does
nothing else. That is worth spelling out, because a meeting reminder is exactly
the kind of app that has no business holding your credentials:

- **No network access.** The app makes no outbound requests of any kind.
- **No credential storage.** It never touches the Keychain, and links no
  security or cryptography frameworks. `otool -L` on the built binary shows
  AppKit, EventKit, ServiceManagement, UserNotifications, and the Foundation
  stack. Nothing else.
- **Read-only calendar access.** It asks for calendar permission, reads
  events, and never writes one.
- **No account of its own.** Your calendar accounts stay where macOS keeps
  them, and macOS does the syncing.

The one file it writes is a capped log at `~/Library/Logs/MeetingNudge.log`.

## Google, Exchange, and iCloud

All of them work, through the account you have already connected in System
Settings › Internet Accounts. EventKit reads the same database Calendar.app
uses, so whatever shows up in Calendar.app shows up here.

There is deliberately no direct Google Calendar API integration. Doing that
would mean an OAuth client, a refresh token, and Keychain storage inside this
app, which is a meaningful amount of attack surface for a reminder. Letting
macOS own the account is both simpler and safer.

The practical trade-off: a meeting you add on your phone appears once macOS has
synced it, which is usually quick but is not instant. If an alert seems late,
the **Up next** panel in settings shows exactly what the app can see right now.
Calendar.app › Settings › General › "Refresh calendars" controls how often
macOS checks.

## Settings

Menu bar icon › Settings, or click the app in Finder.

| Setting | What it does |
|---|---|
| Style | Full screen, corner banner, or notification |
| Warn me | 1, 2, 5 or 10 minutes before the start |
| Clear itself after | Never, or 30, 60 or 150 seconds |
| Remind-at-start button | Pushes the alert back to the meeting's start time |
| Only meetings with a join link | Skips focus blocks and other link-free events |
| Play a sound | On by default |
| Alert me about | Per-calendar switches, grouped by account |
| Launch at login | Registers a login item through SMAppService |

The full screen style blocks clicks on purpose. "Clear itself after" is the
safety net, and setting it to Never means a walk-away leaves the overlay up
until you come back.

## What it alerts on

- Any timed event on a calendar you have left switched on.
- Skips all-day events, cancelled events, and anything you have declined.
- Collapses the same invitation appearing on two calendars into one alert,
  matching on the iCalUID, and keeps whichever copy actually has a join link.
- Finds the join link in the event's URL, location, or notes. Knows Zoom,
  Google Meet, Teams, Webex, Jitsi, Whereby, GoToMeeting, BlueJeans, Chime and
  Slack huddles, and falls back to any link it finds.
- Each occurrence of a repeating meeting alerts once.

## Development

```bash
./build.sh          # builds build/MeetingNudge.app
./test.sh           # 28 unit tests, offline and hermetic
```

`MeetingNudge --preview` raises a sample alert straight away, which is the
quick way to check it really does float above your full screen apps.

| File | What it holds |
|---|---|
| `Sources/main.swift` | Menu bar agent, polling loop, alert dispatch |
| `Sources/Overlay.swift` | The three alert styles |
| `Sources/Settings.swift` | Settings window |
| `Sources/EventKitSource.swift` | Reading the calendar store |
| `Sources/Meeting.swift` | Event model and de-duplication |
| `Sources/Schedule.swift` | When an alert fires |
| `Sources/JoinLink.swift` | Join-link and provider matching |
| `Sources/Log.swift` | The log file |
| `Sources/Prefs.swift` | Preferences |

`Schedule`, `JoinLink` and `Meeting` are pure Foundation, with no AppKit and no
EventKit, which is what lets `test.sh` compile and run them directly.

The build is `swiftc` plus a hand-written bundle layout, then an ad-hoc
signature so macOS remembers your calendar permission between rebuilds.
Notarized releases would need the paid Apple Developer Program, so for now the
install path is a source build.

## Licence

MIT.
