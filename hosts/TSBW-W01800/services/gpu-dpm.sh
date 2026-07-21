#!/bin/bash
# Set GPU DPM based on AC adapter state.
# Called by udev when amdgpu DRM card is added (driver fully loaded).
# Also safe to call at any time — re-reads AC state each invocation.
set -eu

ac=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null || echo 0)
if [ "$ac" = "1" ]; then
  level=auto
else
  level=low
fi

for card in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
  if [ -w "$card" ]; then
    echo "$level" > "$card" 2>/dev/null || true
  fi
done