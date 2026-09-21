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
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

swiftc -O -swift-version 5 \
  -target arm64-apple-macos14.0 \
  -framework AppKit -framework EventKit -framework ServiceManagement \
  -framework UserNotifications \
  -o "$APP/Contents/MacOS/MeetingNudge" \
  Sources/*.swift

# Ad-hoc signature, which arm64 requires in order to run the binary at all.
# Note that it does NOT preserve the calendar permission: an ad-hoc signature's
# designated requirement is tied to the code hash, which changes on every
# build, so macOS asks for calendar access again after each rebuild.
codesign --force --sign - --identifier io.github.hamzam1997.meetingnudge "$APP"

echo "Built $APP"
