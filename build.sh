#!/bin/bash
# Builds MeetingNudge.app. No Xcode project, just swiftc and a bundle layout.
#
# Links only AppKit, EventKit, ServiceManagement and UserNotifications. There
# is deliberately no Security framework, no Keychain use, and no networking
# anywhere in this app: it reads the local calendar database and nothing else.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/MeetingNudge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -O -swift-version 5 \
  -target arm64-apple-macos14.0 \
  -framework AppKit -framework EventKit -framework ServiceManagement \
  -framework UserNotifications \
  -o "$APP/Contents/MacOS/MeetingNudge" \
  Sources/*.swift

# Ad-hoc signature gives a stable identity, so macOS remembers the calendar
# permission across rebuilds instead of asking every time.
codesign --force --sign - --identifier com.github.meetingnudge "$APP"

echo "Built $APP"
