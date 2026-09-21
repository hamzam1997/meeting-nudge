#!/bin/bash
# Turns Resources/icon-1024.png into Resources/AppIcon.icns.
# Only needed after changing the artwork; the .icns is committed.
set -euo pipefail
cd "$(dirname "$0")/.."
SET=$(mktemp -d)/MeetingNudge.iconset
mkdir -p "$SET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/icon-1024.png --out "$SET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size*2)) $((size*2)) Resources/icon-1024.png \
       --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
rm -rf "$(dirname "$SET")"
echo "wrote Resources/AppIcon.icns"
