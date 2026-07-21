# Battery life optimization for TSBW-W01800 (ThinkBook 14 G7 ARP, AMD).
#
# power-profiles-daemon (PPD) stays as the primary power manager — DMS
# widgets switch between power-saver / balanced / performance via PPD's
# D-Bus API. This module adds the things PPD does NOT manage:
#
#   - thermald for AMD DPTF adaptive thermal management
#   - Wi-Fi powersave (rtw89_8852ce)
#   - PCIe ASPM powersave policy (kernel boot param)
#   - VM sysctl tuning (swappiness, dirty ratios)
#   - laptop_mode + device runtime PM (udev rule, battery-only)
#   - powertop + iw + usbutils for manual diagnostics
#
# Do NOT add TLP, auto-cpufreq, or powerManagement.powertop.enable —
# all three conflict with PPD's assertion in nixpkgs.
{ lib, pkgs, ... }:

{
  # thermald — REMOVED: Intel DPTF only, crashes on AMD ("Unsupported
  # cpu model or platform"). AMD thermal management is handled by the
  # kernel's native cpufreq/amd_pstate driver + PPD power profiles.
  # services.thermald.enable = true;

  # Wi-Fi powersave — rtw89_8852ce supports it, saves ~0.5-1W.
  networking.networkmanager.wifi.powersave = true;

  # PCIe ASPM — force powersave policy at boot. The kernel default is
  # "default" (BIOS-controlled), which often leaves links in L0s/L1
  # disabled, wasting ~1-2W on AMD laptops. We need pcie_aspm.policy=
  # (not just pcie_aspm=) to override the sysfs policy at boot — without
  # the .policy= suffix, the param sets the default mode for new devices
  # but doesn't override the active policy shown in
  # /sys/module/pcie_aspm/parameters/policy.
  boot.kernelParams = [ "pcie_aspm.policy=powersave" ];

  # VM sysctl — safe for both AC and battery on an SSD laptop.
  # swappiness=10: prefer keeping apps in RAM, only swap under pressure.
  # dirty_ratio=10 / dirty_background_ratio=5: smaller dirty write buffers
  #   reduce sync latency and let the SSD enter low-power APST sooner.
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.dirty_ratio" = 10;
    "vm.dirty_background_ratio" = 5;
  };

  # udev rules for battery-aware power management.
  # laptop_mode batches disk writes so the SSD can sleep between flushes
  # (5-second timeout). Only on battery — on AC, laptop_mode=0 for lower
  # write latency. Also set device runtime PM to auto at boot so amdgpu
  # and NVMe can autosuspend when idle.
  services.udev.extraRules = ''
    # --- Device runtime PM at boot / on power change ---
    # amdgpu + NVMe: allow autosuspend when idle (safe on both AC/battery).
    # NOTE: udev interprets $$  as a literal $ passed to the shell.
    ACTION=="add|change", SUBSYSTEM=="power_supply", RUN+="/bin/sh -c 'for d in /sys/class/drm/card*/device/power/control /sys/class/nvme/*/device/power/control; do [ -w \"$$d\" ] && echo auto > \"$$d\" 2>/dev/null; done'"

    # --- laptop_mode on battery (batch writes → SSD sleeps) ---
    SUBSYSTEM=="power_supply", ATTR{online}=="0", RUN+="/bin/sh -c 'echo 5 > /proc/sys/vm/laptop_mode'"
    SUBSYSTEM=="power_supply", ATTR{online}=="1", RUN+="/bin/sh -c 'echo 0 > /proc/sys/vm/laptop_mode'"
  '';

  # Diagnostic tools — just the binaries, NOT the powertop auto-tune
  # service (powerManagement.powertop.enable conflicts with PPD).
  # powertop: see per-device power consumers, manually tune.
  # iw: check/set Wi-Fi powersave state.
  # usbutils: lsusb to identify USB power hogs.
  environment.systemPackages = with pkgs; [
    powertop
    iw
    usbutils
  ];
}