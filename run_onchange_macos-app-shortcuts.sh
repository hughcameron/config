#!/bin/bash
# Configure macOS app-level keyboard shortcuts via NSUserKeyEquivalents
# Modifiers: @ = Cmd, ^ = Ctrl, $ = Shift, ~ = Option
#
# hash: 2026-04-06-v1

set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Skipping macOS app shortcuts on non-macOS system"
  exit 0
fi

echo "Setting macOS app shortcuts..."

# Zed — system window tab navigation (Cmd+Ctrl+Shift+] / [)
/usr/libexec/PlistBuddy -c 'Delete :NSUserKeyEquivalents' ~/Library/Preferences/dev.zed.Zed.plist 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :NSUserKeyEquivalents dict' ~/Library/Preferences/dev.zed.Zed.plist
/usr/libexec/PlistBuddy -c 'Add :NSUserKeyEquivalents:"Show Next Tab" string "@^$]"' ~/Library/Preferences/dev.zed.Zed.plist
/usr/libexec/PlistBuddy -c 'Add :NSUserKeyEquivalents:"Show Previous Tab" string "@^$["' ~/Library/Preferences/dev.zed.Zed.plist

echo "Done."
