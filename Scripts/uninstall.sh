#!/bin/bash
set -euo pipefail

LABEL="com.company.qrreader"
PLIST="/Library/LaunchAgents/$LABEL.plist"
BIN_DIR="/usr/local/libexec/$LABEL"
TARGET_UID=$(stat -f %u /dev/console || echo "")

if [ -n "$TARGET_UID" ] && [ -f "$PLIST" ]; then
  launchctl bootout gui/$TARGET_UID "$PLIST" || true
fi

rm -f "$PLIST"
rm -rf "$BIN_DIR"

echo "uninstalled: $LABEL"
