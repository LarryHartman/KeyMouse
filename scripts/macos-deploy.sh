#!/bin/bash
# Rebuild the GUI target (picks up Info.plist changes), bundle all Qt
# frameworks and plugins into Deskflow.app, re-sign, and copy to /Applications.
#
# Usage: scripts/macos-deploy.sh [path/to/Qt/bin/macdeployqt]
# Default macdeployqt: ~/Qt/*/macos/bin/macdeployqt, else Homebrew's.

set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO_DIR/build/bin/Deskflow.app"
DEST="/Applications/Deskflow.app"

MDQ="${1:-}"
if [ -z "$MDQ" ]; then
  MDQ="$(ls -d "$HOME"/Qt/*/macos/bin/macdeployqt 2>/dev/null | tail -1 || true)"
fi
if [ -z "$MDQ" ] && command -v brew >/dev/null 2>&1; then
  MDQ="$(brew --prefix qt)/bin/macdeployqt"
fi
[ -x "$MDQ" ] || { echo "!!  macdeployqt not found; pass its path as the first argument."; exit 1; }

echo "==> Rebuilding"
cmake --build "$REPO_DIR/build"

echo "==> Deploying Qt into bundle with $MDQ"
"$MDQ" "$APP" -executable="$APP/Contents/MacOS/deskflow-core" -always-overwrite

echo "==> Signing and installing"
codesign --force --deep --sign - "$APP"
osascript -e 'quit app "Deskflow"' 2>/dev/null || true
sleep 2
rm -rf "$DEST"
cp -R "$APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
echo "==> Installed $DEST"
echo "    Re-sign changed the binary: re-grant Accessibility and Input Monitoring if prompted."
