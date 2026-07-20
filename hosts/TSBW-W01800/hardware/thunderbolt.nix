# Thunderbolt / USB4 support
{ pkgs, ... }: {
  # Bolt daemon for Thunderbolt device authorization
  services.hardware.bolt.enable = true;

  # Load Thunderbolt module early in initrd so the dock is visible
  # before amdgpu probes DisplayPort MST topology
  boot.initrd.kernelModules = [ "thunderbolt" ];

  # Authorize Thunderbolt devices in initrd, BEFORE amdgpu loads and
  # claims DP adapters. Without this, the dock isn't authorized until
  # bolt runs in userspace, by which point amdgpu has already claimed
  # the only DP OUT adapter. The second DP tunnel then fails with
  # "failed to allocate DP resource for port 7".
  boot.initrd.systemd.services.thunderbolt-authorize = {
    description = "Authorize Thunderbolt devices";
    wantedBy = [ "initrd.target" ];
    before = [ "sysinit.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    unitConfig = {
      DefaultDependencies = false;
    };
    # Use sh explicitly — the initrd may not have bash linked yet.
    # Don't fail if /sys/bus/thunderbolt/devices/ is empty or doesn't exist;
    # just keep waiting until unauthorized devices appear.
    script = ''
      i=0
      while [ $i -lt 40 ]; do
        authorized_something=0
        for dev in /sys/bus/thunderbolt/devices/*/authorized; do
          [ -f "$dev" ] || continue
          val="$(cat "$dev" 2>/dev/null)" || continue
          if [ "$val" = "0" ]; then
            echo 1 > "$dev" 2>/dev/null || true
            authorized_something=1
          fi
        done
        if [ $authorized_something -eq 1 ]; then
          break
        fi
        i=$((i + 1))
        sleep 0.5
      done
      exit 0
    '';
  };

  # Also auto-authorize from udev as a fallback (for hot-plug after boot)
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}=="thunderbolt_device", ATTR{authorized}=="0", RUN+="${pkgs.bash}/bin/sh -c 'echo 1 > /sys$devpath/authorized'"

    # Reprobe DRM connectors when a Thunderbolt device is authorized.
    # udevadm verify (systemd 261) rejects ACTION=="add|change" — a pipe list
    # is not a valid value for ACTION in udev rules — so emit two rules.
    ACTION=="add", SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}=="thunderbolt_device", ATTR{authorized}=="1", RUN+="${pkgs.bash}/bin/sh -c 'for c in /sys/class/drm/card*-*/status; do echo detect > $$c 2>/dev/null; done'"
    ACTION=="change", SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}=="thunderbolt_device", ATTR{authorized}=="1", RUN+="${pkgs.bash}/bin/sh -c 'for c in /sys/class/drm/card*-*/status; do echo detect > $$c 2>/dev/null; done'"
  '';
}