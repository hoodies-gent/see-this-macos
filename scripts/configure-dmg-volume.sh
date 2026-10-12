#!/bin/bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: configure-dmg-volume.sh DEVICE MOUNT_POINT FINAL_VOLUME_NAME" >&2
  exit 2
fi

DEVICE=$1
MOUNT_POINT=$2
FINAL_VOLUME_NAME=$3

osascript scripts/configure-dmg.applescript "$MOUNT_POINT"

if [[ ! -f "$MOUNT_POINT/.DS_Store" ]]; then
  echo "Finder did not write DMG layout metadata to $MOUNT_POINT." >&2
  exit 1
fi

diskutil renameVolume "$DEVICE" "$FINAL_VOLUME_NAME" >/dev/null
sync
