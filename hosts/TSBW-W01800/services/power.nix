# Battery life optimization for TSBW-W01800 (ThinkBook 14 G7 ARP, AMD).
#
# power-profiles-daemon (PPD) stays as the primary power manager — DMS
# widgets switch between power-saver / balanced / performance via PPD's
# D-Bus API. This module adds the things PPD does NOT manage:
#
#   - Wi-Fi powersave (rtw89_8852ce)
#   - PCIe ASPM powersave policy (kernel boot param)
#   - NVMe APST (Autonomous Power State Transition — SSD sleeps when idle)
#   - VM sysctl tuning (swappiness, dirty ratios)
#   - All-PCI-device runtime PM (udev rule, autosuspend when idle)
#   - USB device autosuspend (dock peripherals, camera, BT — all 'auto')
#   - PCI wakeup source pruning (only essential devices can wake from suspend)
#   - GPU DPM force 'low' on battery (udev on DRM add + systemd service)
#   - laptop_mode on battery (udev rule, batch writes → SSD sleeps)
#   - system76-scheduler (CFS profile tuning on/off battery)
#   - Audio codec power save (snd_hda_intel power_save=1)
#   - NMI watchdog disable (fewer timer interrupts → deeper C-states)
#   - Bluetooth USB autosuspend (btusb suspends when no devices paired)
#   - Suspend-then-hibernate after 1h (zero overnight battery drain)
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

  # system76-scheduler — userspace CPU/IO scheduler optimizer.
  # Tweaks CFS latency parameters when switching on/off battery via PPD.
  # Improves performance-per-watt without reducing functionality — the
  # CPU spends more time in idle states without losing responsiveness.
  # Does NOT conflict with PPD (it listens to PPD's D-Bus signals).
  services.system76-scheduler = {
    enable = true;
    settings.cfsProfiles.enable = true;  # default, explicit for clarity
  };

  # Audio codec power save — snd_hda_intel suspends the HDA codec after
  # 1 second of silence. The codec is a common powertop top-offender,
  # drawing ~0.5-1W even when no audio is playing. Audio still works
  # instantly when needed (may produce a faint pop on some codecs —
  # increase to power_save=5 if that's bothersome).
  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=1
    # Bluetooth USB autosuspend — btusb module suspends when no BT
    # devices are connected. Saves ~0.2-0.5W. Devices pair/wake
    # normally when needed.
    options btusb enable_autosuspend=1
  '';

  # NMI watchdog disable — the watchdog generates periodic interrupts
  # that prevent CPU cores from reaching deep C-states. Disabling it
  # has zero functional impact (it's only for kernel-hang debugging)
  # and saves ~0.1-0.3W.
  boot.kernel.sysctl."kernel.nmi_watchdog" = 0;

  # Suspend-then-hibernate — after suspending, systemd transitions to
  # hibernate (RAM → swap, full power-off) after 1 hour. Fast resume
  # for short suspend, zero battery drain for overnight/long suspend.
  # Requires working hibernation (swap device configured — we have
  # LUKS swap + zram).
  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "1h";
  };

  # PCIe ASPM — force powersave policy at boot. The kernel default is
  # "default" (BIOS-controlled), which often leaves links in L0s/L1
  # disabled, wasting ~1-2W on AMD laptops. We need pcie_aspm.policy=
  # (not just pcie_aspm=) to override the sysfs policy at boot — without
  # the .policy= suffix, the param sets the default mode for new devices
  # but doesn't override the active policy shown in
  # /sys/module/pcie_aspm/parameters/policy.
  boot.kernelParams = [
    "pcie_aspm.policy=powersave"

    # NVMe APST — force Autonomous Power State Transitions so the SSD
    # drops to lower power states on its own when idle. The kernel
    # default may leave APST disabled if the NVMe firmware advertises
    # questionable latency values. force_apst=1 overrides this and
    # enables APST unconditionally. Saves ~0.3-0.5W on an idle SSD.
    "nvme_core.force_apst=1"
  ];

  # VM sysctl — safe for both AC and battery on an SSD laptop.
  # swappiness=10: prefer keeping apps in RAM, only swap under pressure.
  # dirty_ratio=10 / dirty_background_ratio=5: smaller dirty write buffers
  #   reduce sync latency and let the SSD enter low-power APST sooner.
  # dirty_writeback_centisecs=1500: flush dirty pages every 15s (default 5s)
  #   so the SSD stays idle longer between write flushes. Recommended by
  #   powertop.
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.dirty_ratio" = 10;
    "vm.dirty_background_ratio" = 5;
    "vm.dirty_writeback_centisecs" = 1500;
  };

  # udev rules for battery-aware power management.
  #
  # 1. All PCI devices → runtime PM 'auto' (autosuspend when idle).
  #    powertop recommends this for every PCI device on this laptop —
  #    AMD chipset bridges, Data Fabric functions, WiFi, Ethernet, SD
  #    reader, IOMMU, SMBus, PSP/CCP, etc. Previously we only set amdgpu
  #    + NVMe; expanding to all PCI devices saves ~1.5-2.5W.
  # 2. All USB devices → runtime PM 'auto' (autosuspend when idle).
  #    Covers dock peripherals (keyboard, mouse, dock audio, dock MCU,
  #    dock LAN), internal camera, fingerprint reader, and Bluetooth.
  #    Devices resume instantly on access. The keyboard keeps wakeup
  #    enabled so it can wake the system from suspend.
  # 3. PCI wakeup source pruning — disable wakeup on non-essential PCI
  #    devices to prevent spurious wakeups during suspend:
  #    - AMD PCIe GPP bridges (0x1022:0x14ba, 0x1022:0x14cd) — bridges
  #      themselves don't need to wake the system
  #    - Intel JHL6540 Thunderbolt 3 bridge (0x8086:0x15d3) — dock bridge
  #    - Fresco Logic FL1100 USB controllers (0x1b73:0x1100) — dock USB
  #    - AMD internal USB xHCI controllers (0x1022:0x161f, 0x15d6, 0x15d7)
  #    - AMD USB2 controllers (0x1022:0x162f)
  #    Lid open, power button, and the dock keyboard still wake normally.
  # GPU DPM on battery — udev rule on DRM subsystem.
  #
  # amdgpu's power_dpm_force_performance_level stays 'auto' and
  # power_dpm_state stays 'performance' even in PPD power-saver mode.
  # We force 'low' on battery so the GPU uses lowest clock states.
  # Restored to 'auto' on AC for full GPU performance.
  #
  # This fires when the DRM card device is added (i.e. amdgpu is loaded
  # and ready), not on power_supply events which fire too early at boot.
  # The power-battery-tune systemd service also re-applies this on
  # power source changes (see below).
  #
  # NOTE: CPU boost (cpufreq/boost) is NOT touched anywhere. PPD 0.30
  # with amd_pstate_epp only controls EPP (not boost), but writing boost
  # before PPD starts causes PPD to crash with EINVAL when it probes
  # per-policy boost files. PPD setting EPP=power is far more important
  # than boost=0 — it drops idle freq to 416MHz and prevents boost under
  # load. Writing boost would crash PPD and leave EPP stuck at
  # balance_performance, which is much worse.
  services.udev.extraRules = ''
    # --- All PCI device runtime PM at boot ---
    # Set every PCI device to 'auto' so they can autosuspend when idle.
    # Fires at boot when PCI devices are discovered (ACTION=="add").
    ACTION=="add", SUBSYSTEM=="pci", RUN+="/bin/sh -c 'for d in /sys/bus/pci/devices/*/power/control; do [ -w \"$$d\" ] && echo auto > \"$$d\" 2>/dev/null; done'"

    # --- All USB device runtime PM at boot ---
    # Set every USB device to 'auto' so they can autosuspend when idle.
    # This catches dock peripherals (keyboard, mouse, dock audio, dock
    # MCU, dock LAN), internal camera, fingerprint reader, and Bluetooth.
    # Devices resume instantly on access — no functional impact.
    ACTION=="add", SUBSYSTEM=="usb", RUN+="/bin/sh -c 'for d in /sys/bus/usb/devices/*/power/control; do [ -w \"$$d\" ] && echo auto > \"$$d\" 2>/dev/null; done'"

    # --- PCI wakeup source pruning ---
    # Disable wakeup on non-essential PCI devices to prevent spurious
    # wakeups during suspend. Match by vendor:device ID — interface
    # names may not be assigned at udev "add" time.
    # AMD PCIe GPP bridges (0x1022:0x14ba, 0x1022:0x14cd)
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1022", ATTR{device}=="0x14ba", RUN+="/bin/sh -c 'echo disabled > /sys$devpath/power/wakeup 2>/dev/null'"
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1022", ATTR{device}=="0x14cd", RUN+="/bin/sh -c 'echo disabled > /sys$devpath/power/wakeup 2>/dev/null'"
    # Intel JHL6540 Thunderbolt 3 bridge (0x8086:0x15d3) — dock bridge
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x15d3", RUN+="/bin/sh -c 'echo disabled > /sys$devpath/power/wakeup 2>/dev/null'"
    # Fresco Logic FL1100 USB 3.0 controllers (0x1b73:0x1100) — dock USB
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1b73", ATTR{device}=="0x1100", RUN+="/bin/sh -c 'echo disabled > /sys$devpath/power/wakeup 2>/dev/null'"
    # AMD internal USB xHCI controllers (0x1022:0x161f, 0x15d6, 0x15d7)
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1022", ATTR{device}=="0x161f", RUN+="/bin/sh -c 'echo disabled > /sys$devpath/power/wakeup 2>/dev/null'"
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1022", ATTR{device}=="0x15d6", RUN+="/bin/sh -c 'echo disabled > /sys$devpath/power/wakeup 2>/dev/null'"
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1022", ATTR{device}=="0x15d7", RUN+="/bin/sh -c 'echo disabled > /sys$devpath/power/wakeup 2>/dev/null'"
    # AMD USB2 controllers (0x1022:0x162f)
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1022", ATTR{device}=="0x162f", RUN+="/bin/sh -c 'echo disabled > /sys$devpath/power/wakeup 2>/dev/null'"

    # --- laptop_mode on battery (batch writes → SSD sleeps) ---
    # Split into add/change rules — udevadm verify (systemd 261) rejects
    # pipe lists for ACTION (see thunderbolt.nix for the same pattern).
    SUBSYSTEM=="power_supply", ACTION=="add", ATTR{online}=="0", RUN+="/bin/sh -c 'echo 5 > /proc/sys/vm/laptop_mode'"
    SUBSYSTEM=="power_supply", ACTION=="add", ATTR{online}=="1", RUN+="/bin/sh -c 'echo 0 > /proc/sys/vm/laptop_mode'"
    SUBSYSTEM=="power_supply", ACTION=="change", ATTR{online}=="0", RUN+="/bin/sh -c 'echo 5 > /proc/sys/vm/laptop_mode'"
    SUBSYSTEM=="power_supply", ACTION=="change", ATTR{online}=="1", RUN+="/bin/sh -c 'echo 0 > /proc/sys/vm/laptop_mode'"

    # --- Disable Wake-on-LAN on Ethernet + WiFi ---
    # Prevents network interfaces from waking the laptop from suspend.
    # Lid open, keyboard, and power button still wake normally.
    # Match by PCI vendor:device ID instead of interface name — the net
    # interface name may not be assigned yet at udev "add" time for PCI
    # devices. Realtek RTL8111 Ethernet = 10ec:8168,
    # Realtek RTL8852CE WiFi = 10ec:c852.
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10ec", ATTR{device}=="0x8168", RUN+="/bin/sh -c 'echo disabled > /sys$devpath/power/wakeup 2>/dev/null'"
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10ec", ATTR{device}=="0xc852", RUN+="/bin/sh -c 'echo disabled > /sys$devpath/power/wakeup 2>/dev/null'"

    # --- GPU DPM on DRM card add (amdgpu ready) ---
    # When amdgpu loads and creates the DRM card device, set GPU DPM to
    # 'low' if on battery. This fires after amdgpu is fully initialized,
    # unlike power_supply events which fire too early at boot.
    # Uses a helper script because udev's $$ substitution doesn't support
    # shell $() command substitution inside RUN+=.
    ACTION=="add", SUBSYSTEM=="drm", KERNEL=="card[0-9]", RUN+="${pkgs.bash}/bin/bash ${./gpu-dpm.sh}"

    # --- GPU DPM on power source change ---
    # Trigger the power-battery-tune service to re-apply GPU DPM when
    # power source changes. The service runs after PPD to avoid conflicts.
    SUBSYSTEM=="power_supply", ACTION=="change", RUN+="/bin/sh -c 'systemctl start power-battery-tune.service 2>/dev/null || true'"
  '';

  # GPU DPM on battery — systemd service for power source changes.
  #
  # Re-applies GPU DPM when power source changes (unplug/plug AC).
  # The initial boot-time setting is done by the DRM udev rule above.
  # This service handles runtime transitions.
  #
  # CPU boost is NOT set here — see note above about PPD crash.
  systemd.services.power-battery-tune = {
    description = "Set GPU DPM low on battery";
    after = [ "power-profiles-daemon.service" "systemd-udevd.service" ];
    wantedBy = [ "graphical.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
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
    '';
  };

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