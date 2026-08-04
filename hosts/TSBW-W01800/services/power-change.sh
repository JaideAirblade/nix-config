#!/bin/bash
# Debounced power-source-change handler for udev.
#
# udev fires many power_supply "change" events at boot as drivers initialize
# the battery/AC sysfs entries.  Each event triggered `systemctl restart` on
# three battery-aware services, causing dozens of restarts within seconds and
# hitting systemd's start rate limit — which left dnsproxy in failed state.
#
# This script reads the current AC state and only restarts the services if the
# state actually changed since the last invocation.  The state is persisted in
# /run/power-change/last-ac so consecutive events with the same state are
# no-ops.
#
# Called by the udev rule in power.nix on SUBSYSTEM=="power_supply" ACTION=="change".
set -eu

STATE_DIR=/run/power-change
STATE_FILE="$STATE_DIR/last-ac"

# Read current AC state (0 = battery, 1 = AC)
ac=0
for supply in /sys/class/power_supply/*; do
  [ "$(cat "$supply/type" 2>/dev/null)" = "Mains" ] || continue
  if [ "$(cat "$supply/online" 2>/dev/null)" = "1" ]; then
    ac=1
    break
  fi
done

# Read last known state
mkdir -p "$STATE_DIR"
last_ac=""
[ -f "$STATE_FILE" ] && last_ac=$(cat "$STATE_FILE" 2>/dev/null || echo "")

# If state hasn't changed, do nothing — this is the debounce.
if [ "$last_ac" = "$ac" ]; then
  exit 0
fi

# State changed — persist it and restart battery-aware services.
echo "$ac" > "$STATE_FILE"

systemctl restart power-battery-tune.service 2>/dev/null || true
systemctl restart dnsproxy-battery.service 2>/dev/null || true
systemctl restart services-battery.service 2>/dev/null || true