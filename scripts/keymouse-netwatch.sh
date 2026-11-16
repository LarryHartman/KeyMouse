#!/bin/bash
# KeyMouse network watcher (client side).
#
# Runs on every network change (launchd WatchPaths). Decides whether this Mac
# has a wired path to the server and, if so, pins a host route to the server
# out the wired interface so traffic never drifts onto Wi-Fi. When the wire is
# gone it removes the pin so Wi-Fi carries it. Either way it restarts the
# deskflow-core client so it reconnects over the new path right away instead
# of waiting for the keepalive to time out.
#
# Installed by macos-install.sh; not meant to be run by hand, but harmless if
# you do:  keymouse-netwatch.sh <server-ip>

set -u
SERVER_IP="${1:-}"
[ -n "$SERVER_IP" ] || { echo "usage: $0 <server-ip>"; exit 1; }

LABEL="org.deskflow.keymouse"
STATE="$HOME/Library/Deskflow/netwatch.state"
LOG="$HOME/Library/Deskflow/keymouse-netwatch.log"
mkdir -p "$(dirname "$STATE")"
log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*" >> "$LOG"; }

# Debounce: launchd fires several times per change. Wait for things to settle.
sleep 2

# Identify Wi-Fi device(s) so we can exclude them.
WIFI_DEVS="$(networksetup -listallhardwareports 2>/dev/null \
  | awk '/Hardware Port: Wi-Fi/{getline; print $2}')"

# Find a non-Wi-Fi interface that is up and holds a private LAN address.
WIRED_IF=""
for ifc in $(ifconfig -l); do
  case " $WIFI_DEVS " in *" $ifc "*) continue;; esac
  case "$ifc" in lo*|bridge*|utun*|awdl*|llw*|gif*|stf*|ap*|anpi*|vmenet*|p2p*) continue;; esac
  if ifconfig "$ifc" 2>/dev/null | grep -q "status: active" && \
     ifconfig "$ifc" 2>/dev/null | grep -qE "inet (10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)"; then
    WIRED_IF="$ifc"; break
  fi
done

# Can the wired interface actually reach the server? (ARP/route test)
if [ -n "$WIRED_IF" ]; then
  if ! ping -c 1 -W 1000 -b "$WIRED_IF" "$SERVER_IP" >/dev/null 2>&1; then
    log "wired $WIRED_IF is up but cannot reach $SERVER_IP; treating as no wire"
    WIRED_IF=""
  fi
fi

NEW_STATE="wifi"
[ -n "$WIRED_IF" ] && NEW_STATE="wired:$WIRED_IF"
OLD_STATE="$(cat "$STATE" 2>/dev/null || echo "")"

if [ "$NEW_STATE" = "$OLD_STATE" ]; then
  exit 0
fi
log "path change: ${OLD_STATE:-none} -> $NEW_STATE"
echo "$NEW_STATE" > "$STATE"

# Pin or unpin the host route. Needs root for `route`; use sudo -n so it is a
# no-op (logged) if the sudoers rule from the installer is missing.
if [ -n "$WIRED_IF" ]; then
  sudo -n route -n delete -host "$SERVER_IP" >/dev/null 2>&1
  if sudo -n route -n add -host "$SERVER_IP" -interface "$WIRED_IF" >/dev/null 2>&1; then
    log "pinned $SERVER_IP via $WIRED_IF"
  else
    log "could not pin route (sudo rule missing?); relying on service order"
  fi
else
  sudo -n route -n delete -host "$SERVER_IP" >/dev/null 2>&1 && log "unpinned $SERVER_IP"
fi

# Reconnect the client now.
launchctl kickstart -k "gui/$(id -u)/$LABEL" 2>/dev/null && log "restarted client"
exit 0
