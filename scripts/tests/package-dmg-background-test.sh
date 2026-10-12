#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../.."

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

BACKGROUND="$TEST_DIR/dmg-background.png"
xcrun swift scripts/render-dmg-background.swift "$BACKGROUND"
xcrun swift scripts/tests/verify-dmg-background.swift "$BACKGROUND"
