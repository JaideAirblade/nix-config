#!/usr/bin/env bash
# live-patch-captive-dispatcher.sh — stop Helium spam NOW.
#
# The new dispatcher (only reacts to PORTAL state on WiFi
# interfaces via connectivity-change) is in modules/network/network.nix
# and will be applied to /etc/NetworkManager/dispatcher.d/30-captive-portal.sh
# the next time you run `just up UwU` in a real terminal.
#
# Until then, this script live-installs the fixed dispatcher so
# Helium stops opening with 1.1.1.1 on a working LAN. The old
# dispatcher opened Helium on every DHCP renew because it reacted
# to BOTH `connectivity-change` AND `up` events, AND to both
# `PORTAL` and `LIMITED` states.
#
# Usage: sudo bash scripts/live-patch-captive-dispatcher.sh
#
# Idempotent. Safe to run multiple times. Drop after `just up
# UwU` is run.
set -euo pipefail

LIVE=/etc/NetworkManager/dispatcher.d/30-captive-portal.sh
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

cat > "$TMP" <<'DISPATCHER'
#!/bin/sh
# Open captive portal login page when NM detects PORTAL state.
# $1 = interface, $2 = action
#
# Only react to `connectivity-change` (not `up`) and only to
# PORTAL (not LIMITED). Captive portals are a WiFi phenomenon —
# skip non-WiFi interfaces so LAN users never see a stray Helium
# tab. Uses systemd-run (not su) because su requires a TTY.
#
# Live-patched 2026-08-17 while waiting for the new NixOS
# generation to be activated. Same logic as the Nix-managed
# version in modules/network/network.nix; delete this once
# `just up UwU` has been run.
export PATH="/run/current-system/sw/bin:/run/wrappers/bin:$PATH"

# Captive portals are WiFi-only.
case "$1" in
  wlan*|wlp*|wifi*) ;;
  *) exit 0 ;;
esac

# Only react to connectivity-change, not up.
if [ "$2" != "connectivity-change" ]; then
  exit 0
fi

# Only PORTAL — LIMITED means the probe failed, not a portal.
case "$CONNECTIVITY_STATE" in
  PORTAL) ;;
  *) exit 0 ;;
esac

# Find active Wayland sessions and launch browser as each user.
loginctl --no-legend list-sessions 2>/dev/null | while read -r sess uid user seat type; do
  [ -n "$uid" ] || continue
  runtime="/run/user/$uid"
  [ -d "$runtime" ] || continue

  wl_display=""
  for d in "$runtime"/wayland-*; do
    [ -S "$d" ] || continue
    wl_display=$(basename "$d")
    break
  done
  [ -n "$wl_display" ] || continue

  systemd-run --uid="$uid" --collect --quiet \
    --property=Environment=XDG_RUNTIME_DIR="$runtime" \
    --property=Environment=WAYLAND_DISPLAY="$wl_display" \
    --property=Environment=DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus" \
    -- helium http://1.1.1.1 2>/dev/null &
done
DISPATCHER

install -m 0755 "$TMP" "$LIVE"
echo "Patched $LIVE"
echo
echo "Restart NetworkManager to apply:"
echo "  sudo systemctl reload NetworkManager"
echo "  (or just reconnect to the WiFi network)"
echo
echo "Drop this script after running 'just up UwU' from a real"
echo "terminal — the Nix-managed version takes over from there."