#!/bin/bash
# Set GPU DPM + CPU freq based on AC adapter state.
# Called by udev when amdgpu DRM card is added (driver fully loaded).
# Also safe to call at any time — re-reads AC state each invocation.
#
# Handles both amd_pstate modes:
#   - active: sets EPP=power on battery (PPD 0.30 crash fallback)
#   - guided: sets scaling_min_freq/scaling_max_freq directly (no EPP sysfs)
set -eu

ac=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null || echo 0)
if [ "$ac" = "1" ]; then
  gpu_level=auto
else
  gpu_level=low
fi

# GPU DPM — force lowest clock states on battery
for card in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
  if [ -w "$card" ]; then
    echo "$gpu_level" > "$card" 2>/dev/null || true
  fi
done

# CPU frequency management
if [ -w /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference ]; then
  # Active mode — use EPP
  if [ "$ac" = "1" ]; then
    epp=balance_performance
  else
    epp=power
  fi
  for cpu in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [ -w "$cpu" ] && echo "$epp" > "$cpu" 2>/dev/null || true
  done
else
  # Guided mode — use frequency limits
  if [ "$ac" = "1" ]; then
    min_freq=""
    max_freq=""
  else
    min_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq 2>/dev/null || echo "")
    max_freq="3301000"
  fi
  for cpu_min in /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq; do
    if [ -n "$min_freq" ] && [ -w "$cpu_min" ]; then
      echo "$min_freq" > "$cpu_min" 2>/dev/null || true
    fi
  done
  for cpu_max in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
    if [ -n "$max_freq" ] && [ -w "$cpu_max" ]; then
      echo "$max_freq" > "$cpu_max" 2>/dev/null || true
    elif [ -z "$max_freq" ] && [ -w "$cpu_max" ]; then
      echo "$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)" > "$cpu_max" 2>/dev/null || true
    fi
  done
fi