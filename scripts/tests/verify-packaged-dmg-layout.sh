#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../.."

if [[ $# -ne 1 ]]; then
  echo "Usage: verify-packaged-dmg-layout.sh DMG_PATH" >&2
  exit 2
fi

DMG_PATH=$1
DEVICE=""
MOUNT_POINT=""

cleanup() {
  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" -quiet || true
  fi
}
trap cleanup EXIT

ATTACH_OUTPUT=$(hdiutil attach -readonly -noverify -noautoopen "$DMG_PATH")
DEVICE=$(awk '/\/Volumes\// { print $1; exit }' <<<"$ATTACH_OUTPUT")
MOUNT_POINT=$(awk '/\/Volumes\// { print substr($0, index($0, "/Volumes/")); exit }' <<<"$ATTACH_OUTPUT")

for _ in {1..20}; do
  if [[ $(osascript - "$MOUNT_POINT" <<'APPLESCRIPT'
on run argv
  set volumeAlias to POSIX file (item 1 of argv) as alias
  tell application "Finder" to return exists folder volumeAlias
end run
APPLESCRIPT
) == "true" ]]; then
    break
  fi
  sleep 0.2
done

test -f "$MOUNT_POINT/.background/dmg-background.png"
test -f "$MOUNT_POINT/.DS_Store"
xcrun swift scripts/tests/verify-dmg-background.swift "$MOUNT_POINT/.background/dmg-background.png"

ACTUAL=$(osascript - "$MOUNT_POINT" <<'APPLESCRIPT'
on run argv
  set volumeAlias to POSIX file (item 1 of argv) as alias
  tell application "Finder"
    set volumeFolder to folder volumeAlias
    open volumeFolder
    delay 1
    set dmgWindow to container window of volumeFolder
    set appPosition to position of item "SeeThis.app" of volumeFolder
    set applicationsPosition to position of item "Applications" of volumeFolder
    set viewOptions to icon view options of dmgWindow
    set resultText to ((item 1 of appPosition) as text) & "," & ((item 2 of appPosition) as text)
    set resultText to resultText & "|" & ((item 1 of applicationsPosition) as text) & "," & ((item 2 of applicationsPosition) as text)
    set resultText to resultText & "|" & ((icon size of viewOptions) as text)
    set resultText to resultText & "|" & ((toolbar visible of dmgWindow) as text)
    set resultText to resultText & "|" & ((statusbar visible of dmgWindow) as text)
    close dmgWindow
    return resultText
  end tell
end run
APPLESCRIPT
)

EXPECTED="140,180|400,180|96|false|false"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "Expected packaged DMG layout '$EXPECTED', got '$ACTUAL'." >&2
  exit 1
fi
