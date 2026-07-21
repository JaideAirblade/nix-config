#!/bin/bash
# Set USB device runtime PM based on AC adapter state.
# Called by udev when USB devices are added (boot or hotplug).
#
# On battery: set all USB devices to 'auto' (autosuspend when idle).
# On AC: do nothing — leave devices at 'on' (default, no autosuspend).
# The power-battery-tune service handles the AC/battery transition.
set -eu

ac=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null || echo 0)
if [ "$ac" = "0" ]; then
  for d in /sys/bus/usb/devices/*/power/control; do
    [ -w "$d" ] && echo auto > "$d" 2>/dev/null || true
  done
fi