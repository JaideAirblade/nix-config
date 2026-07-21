#!/bin/bash
# Set GPU DPM + EPP based on AC adapter state.
# Called by udev when amdgpu DRM card is added (driver fully loaded).
# Also safe to call at any time — re-reads AC state each invocation.
#
# Sets EPP=power on battery as a fallback for PPD 0.30, which crashes
# on amd_pstate_epp active mode (EINVAL writing per-policy boost) and
# never gets to set EPP. Without this, EPP stays at balance_performance
# and idle CPU freq is 1.1GHz instead of 416MHz.
set -eu

ac=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null || echo 0)
if [ "$ac" = "1" ]; then
  gpu_level=auto
  epp=balance_performance
else
  gpu_level=low
  epp=power
fi

# GPU DPM — force lowest clock states on battery
for card in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
  if [ -w "$card" ]; then
    echo "$gpu_level" > "$card" 2>/dev/null || true
  fi
done

# EPP fallback — set energy_performance_preference on all CPUs
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
  if [ -w "$cpu" ]; then
    echo "$epp" > "$cpu" 2>/dev/null || true
  fi
done