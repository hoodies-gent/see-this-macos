#!/bin/bash
# Builds a universal, ad-hoc signed Release app and wraps it in a compressed DMG under build/.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=build/DerivedData
STAGE=build/dmg-stage
READ_WRITE_DMG=""
DEVICE=""

cleanup() {
  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" -quiet || true
  fi
  if [[ -n "$READ_WRITE_DMG" ]]; then
    rm -f "$READ_WRITE_DMG"
  fi
  rm -rf "$STAGE" "$DERIVED"
}
trap cleanup EXIT

rm -rf "$DERIVED" "$STAGE"

xcodebuild build \
  -project SeeThis.xcodeproj \
  -scheme SeeThis \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -quiet

APP="$DERIVED/Build/Products/Release/SeeThis.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="build/SeeThis-$VERSION.dmg"
READ_WRITE_DMG="build/SeeThis-$VERSION-read-write.dmg"
BUILD_VOLUME_NAME="SeeThis-build-$$"

ARCHS=$(lipo -archs "$APP/Contents/MacOS/SeeThis")
case "$ARCHS" in
  *arm64*x86_64*|*x86_64*arm64*) ;;
  *) echo "Expected a universal binary, found: $ARCHS" >&2; exit 1 ;;
esac
codesign --verify --deep --strict "$APP"

mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/SeeThis.app"
ln -s /Applications "$STAGE/Applications"
xcrun swift scripts/render-dmg-background.swift "$STAGE/.background/dmg-background.png"

rm -f "$DMG" "$DMG.sha256" "$READ_WRITE_DMG"
hdiutil create -quiet -volname "$BUILD_VOLUME_NAME" -srcfolder "$STAGE" -ov -format UDRW "$READ_WRITE_DMG"

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

bash scripts/configure-dmg-volume.sh "$DEVICE" "$MOUNT_POINT" SeeThis
hdiutil detach "$DEVICE" -quiet
DEVICE=""

hdiutil convert -quiet "$READ_WRITE_DMG" -format UDZO -o "$DMG"

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "Built $DMG ($ARCHS)"
