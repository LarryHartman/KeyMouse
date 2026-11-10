#!/bin/bash
# Install KeyMouse (Deskflow fork) on this Mac for the CURRENT user profile.
#
# Run once in EVERY macOS user profile that should take part. It:
#   1. Copies Deskflow.app to /Applications (first profile only).
#   2. Writes this profile's ~/Library/Deskflow/Deskflow.conf.
#   3. Installs a per-user launch agent.
#
# Modes:
#   scripts/macos-install.sh server              # this Mac owns the keyboard/mouse (iMac)
#   scripts/macos-install.sh client <server-ip>  # this Mac is driven (MacBook)
#
# Client mode runs deskflow-core directly from the launch agent (no GUI).
# On macOS 26+ the GUI-spawned core is blocked by the Local Network
# privacy check; the directly launched core is not.
#
# Optional 3rd arg: path to Deskflow.app (default build/bin/Deskflow.app).

set -euo pipefail

MODE="${1:-}"
SERVER_IP="${2:-}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_APP="${3:-$REPO_DIR/build/bin/Deskflow.app}"
DEST_APP="/Applications/Deskflow.app"
CORE="$DEST_APP/Contents/MacOS/deskflow-core"
LABEL="org.deskflow.keymouse"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT="$AGENT_DIR/$LABEL.plist"
CONF_DIR="$HOME/Library/Deskflow"
CONF="$CONF_DIR/Deskflow.conf"
LOG="$CONF_DIR/keymouse-client.log"

usage() {
  echo "usage: $0 server | client <server-ip> [path/to/Deskflow.app]"
  exit 1
}
[ "$MODE" = "server" ] || { [ "$MODE" = "client" ] && [ -n "$SERVER_IP" ]; } || usage

echo "==> KeyMouse install: mode=$MODE user=$(whoami)"

# 1. App bundle
if [ -d "$DEST_APP" ]; then
  if [ -d "$SRC_APP" ] && [ "$SRC_APP" -nt "$DEST_APP" ]; then
    echo "==> Updating $DEST_APP from $SRC_APP"
    rm -rf "$DEST_APP"; cp -R "$SRC_APP" "$DEST_APP"
  else
    echo "==> Using existing $DEST_APP"
  fi
else
  [ -d "$SRC_APP" ] || { echo "!!  $SRC_APP not found. Build first (scripts/macos-build.sh)."; exit 1; }
  echo "==> Installing $SRC_APP to $DEST_APP"
  cp -R "$SRC_APP" "$DEST_APP"
fi
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

# 2. Per-user config
mkdir -p "$CONF_DIR"; touch "$CONF"
set_key() {
  python3 - "$CONF" "${1%%/*}" "${1#*/}" "$2" <<'PY'
import sys, configparser
path, section, key, value = sys.argv[1:]
cp = configparser.ConfigParser(); cp.optionxform = str; cp.read(path)
if not cp.has_section(section): cp.add_section(section)
cp.set(section, key, value)
with open(path, "w") as f: cp.write(f, space_around_delimiters=False)
PY
}
# LAN only: TLS off on both ends avoids fingerprint mismatches between builds.
set_key security/tlsEnabled false
set_key security/checkPeerFingerprints false
set_key gui/startCoreWithGui true
set_key gui/closeToTray true
set_key gui/enableUpdateCheck false
if [ "$MODE" = "client" ]; then
  set_key client/remoteHost "$SERVER_IP"
  set_key gui/autoHide true
else
  set_key gui/autoHide false
fi
echo "==> Wrote $CONF"

# 3. Launch agent
mkdir -p "$AGENT_DIR"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if [ "$MODE" = "client" ]; then
  # Headless core client; KeepAlive restarts it if it exits.
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$CORE</string>
    <string>client</string>
    <string>$SERVER_IP</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST
else
  # Server: run the GUI so you can edit the screen layout; it starts the core.
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string><string>-g</string><string>-a</string><string>$DEST_APP</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
PLIST
fi
launchctl bootstrap "gui/$(id -u)" "$AGENT"
echo "==> Launch agent installed and started: $AGENT"

echo
if [ "$MODE" = "client" ]; then
  echo "Client running in the background; log: $LOG"
  echo "If macOS asks to allow local network / accessibility / input monitoring, approve it."
  echo "Check:  tail -f $LOG"
else
  echo "Server: open Deskflow, choose 'Use this computer's keyboard and mouse', Configure Server, Start."
fi
