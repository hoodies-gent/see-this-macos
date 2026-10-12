#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../.."

TEST_DIR=$(mktemp -d)
STAGE="$TEST_DIR/stage"
BLOCKER_STAGE="$TEST_DIR/blocker-stage"
READ_WRITE_DMG="$TEST_DIR/layout-test.dmg"
BLOCKER_DMG="$TEST_DIR/layout-blocker.dmg"
FINAL_VOLUME_NAME="SeeThisLayoutTest-$$"
BUILD_VOLUME_NAME="$FINAL_VOLUME_NAME-build"
DEVICE=""
BLOCKER_DEVICE=""
MOUNT_POINT=""

cleanup() {
  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" -quiet || true
  fi
  if [[ -n "$BLOCKER_DEVICE" ]]; then
    hdiutil detach "$BLOCKER_DEVICE" -quiet || true
  fi
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGE/SeeThis.app" "$STAGE/.background" "$BLOCKER_STAGE"
touch "$BLOCKER_STAGE/.keep"
ln -s /Applications "$STAGE/Applications"
xcrun swift scripts/render-dmg-background.swift "$STAGE/.background/dmg-background.png"

hdiutil create \
  -quiet \
  -volname "$BUILD_VOLUME_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDRW \
  "$READ_WRITE_DMG"

hdiutil create \
  -quiet \
  -volname "$FINAL_VOLUME_NAME" \
  -srcfolder "$BLOCKER_STAGE" \
  -ov \
  -format UDRW \
  "$BLOCKER_DMG"

BLOCKER_ATTACH_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$BLOCKER_DMG")
BLOCKER_DEVICE=$(awk '/\/Volumes\// { print $1; exit }' <<<"$BLOCKER_ATTACH_OUTPUT")

ATTACH_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$READ_WRITE_DMG")
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

bash scripts/configure-dmg-volume.sh "$DEVICE" "$MOUNT_POINT" "$FINAL_VOLUME_NAME"
hdiutil detach "$DEVICE" -quiet
DEVICE=""
hdiutil detach "$BLOCKER_DEVICE" -quiet
BLOCKER_DEVICE=""

ATTACH_OUTPUT=$(hdiutil attach -readonly -noverify -noautoopen "$READ_WRITE_DMG")
DEVICE=$(awk '/\/Volumes\// { print $1; exit }' <<<"$ATTACH_OUTPUT")
MOUNT_POINT=$(awk '/\/Volumes\// { print substr($0, index($0, "/Volumes/")); exit }' <<<"$ATTACH_OUTPUT")

test -f "$MOUNT_POINT/.background/dmg-background.png"
test -f "$MOUNT_POINT/.DS_Store"

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
  echo "Expected DMG layout '$EXPECTED', got '$ACTUAL'." >&2
  exit 1
fi
