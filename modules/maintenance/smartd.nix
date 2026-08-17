# Smartd — SMART health monitoring for HDDs and SSDs.
#
# Polls every autodetected disk's SMART attributes every 30 minutes
# and logs/raises a wall notification on:
#   - Reallocated sector count increase (HDD: predict failure)
#   - Current pending sector count > 0 (HDD: bad sectors)
#   - Uncorrectable error count increase (any: bad block)
#   - Temperature warnings (configured per-drive below)
#   - SSD/NVMe endurance-attribute regressions
#
# Why this matters: the UwU-Server has 4 NVMes (Crucial E100 root,
# 2× Lexar NM790, GIGABYTE), TSBW-W01800 has its own NVMe, and UwU
# has at least one. The CHANGELOG explicitly records bus drops and
# runaway NVMe controllers on UwU-Server — exactly what smartd
# catches early. Without this, the first sign of disk death is the
# disk disappearing.
#
# ## Battery caveat (TSBW-W01800)
#
# TSBW-W01800 stops smartd on battery and restarts on AC via its own
# `battery-services.nix` smartd override. That file imports
# `nixos.modules.maintenance` (which now provides smartd) and wraps the
# smartd service with start/stop behavior. Both paths co-exist cleanly
# because smartd's enable flag is the same — TSBW just adds a
# battery-aware unit drop-in.
#
# ## Defaults
#
# The flags below are the smartd-recommended set for mixed
# HDD+SSD+NVMe fleets:
#   -a         : monitor all SMART attributes
#   -o on      : enable automatic offline testing
#   -S on      : enable attribute autosave
#   -n standby: don't poll drives in standby (HDD sleep mode)
#   -W 4,35,40 : warn on temp changes: 4°C delta, 35°C critical-low,
#                40°C critical-high. Lower than the 45°C NVMe spec
#                because the Beelink runs warm and you want a heads-up
#                before thermal throttling kicks in.
#
# Follows the same shape as `modules/disko/btrfs-dedup.nix`: function
# takes `{ ... }:` (no `config` arg), and contributes config only.
_:
{
  nixos.modules.maintenance =
    { ... }:
    {
      services.smartd = {
        enable = true;
        autodetect = true;
        # Monitor all autodetected drives with the recommended flags.
        # Per-drive overrides can be added in host-specific modules.
        defaults.autodetected = "-a -o on -S on -n standby -W 4,35,40";
        # Wall notifications hit every logged-in user — useful on
        # workstations (UwU, TSBW-W01800), less useful headless on
        # UwU-Server but harmless. For server-only alerting, add
        # `notifications = { mail = { ... }; };` per host.
        notifications.wall.enable = true;
      };
      # NOTE: smartmontools is provided by NixOS's smartd module itself
      # as a runtime dep — no explicit environment.systemPackages needed.
    }
  ;
}