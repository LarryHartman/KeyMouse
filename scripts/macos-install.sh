#!/bin/bash
# Install KeyMouse (Deskflow fork) on this Mac for the CURRENT user profile.
#
# Run this once in EVERY macOS user profile that should share the keyboard
# and mouse. It:
#   1. Copies Deskflow.app to /Applications (first profile only; later
#      profiles reuse it).
#   2. Writes a per-user launch agent so the app starts at login for this
#      profile and auto-hides to the menu bar.
#   3. Pre-sets the GUI to auto-start the core and stay in the tray.
#
# Usage:
#   scripts/macos-install.sh [path/to/Deskflow.app]
#   (default: build/bin/Deskflow.app relative to the repo)
#
# After running, open Deskflow once in this profile, pick Client (MacBook)
# or Server (iMac), approve the Accessibility and Input Monitoring prompts,
# and connect. The launch agent keeps it running from then on.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_APP="${1:-$REPO_DIR/build/bin/Deskflow.app}"
DEST_APP="/Applications/Deskflow.app"
LABEL="org.deskflow.keymouse"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT="$AGENT_DIR/$LABEL.plist"
CONF_DIR="$HOME/Library/Deskflow"
CONF="$CONF_DIR/Deskflow.conf"

echo "==> KeyMouse install for user: $(whoami)"

# 1. App bundle
if [ -d "$DEST_APP" ]; then
  if [ -d "$SRC_APP" ] && [ "$SRC_APP" -nt "$DEST_APP" ]; then
    echo "==> Updating $DEST_APP from $SRC_APP"
    rm -rf "$DEST_APP"
    cp -R "$SRC_APP" "$DEST_APP"
  else
    echo "==> Using existing $DEST_APP"
  fi
else
  if [ ! -d "$SRC_APP" ]; then
    echo "!!  $SRC_APP not found and $DEST_APP is not installed."
    echo "    Build first with scripts/macos-build.sh, or pass the .app path."
    exit 1
  fi
  echo "==> Installing $SRC_APP to $DEST_APP"
  cp -R "$SRC_APP" "$DEST_APP"
fi
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

# 2. Per-user config defaults (only keys we care about; GUI owns the rest)
mkdir -p "$CONF_DIR"
touch "$CONF"
set_key() {
  # set_key section/key value  -> writes [section] key=value in INI form
  local section="${1%%/*}" key="${1#*/}" value="$2"
  python3 - "$CONF" "$section" "$key" "$value" <<'PY'
import sys, configparser
path, section, key, value = sys.argv[1:]
cp = configparser.ConfigParser()
cp.optionxform = str
cp.read(path)
if not cp.has_section(section):
    cp.add_section(section)
cp.set(section, key, value)
with open(path, "w") as f:
    cp.write(f, space_around_delimiters=False)
PY
}
set_key gui/startCoreWithGui true
set_key gui/closeToTray true
set_key gui/autoHide true
set_key gui/enableUpdateCheck false
echo "==> Wrote defaults to $CONF"

# 3. Launch agent: start the app at login for this profile
mkdir -p "$AGENT_DIR"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-g</string>
    <string>-a</string>
    <string>$DEST_APP</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$AGENT"
echo "==> Launch agent installed: $AGENT"

echo
echo "Done. Now open Deskflow in this profile, choose Client or Server,"
echo "and approve the Accessibility and Input Monitoring prompts."
echo "Repeat this script in each other profile on this Mac."
