# AOC AG344UXM EDID override.
#
# The AOC AG344UXM (3440x1440 ultrawide) only declares 60Hz over HDMI when
# connected directly — its native 91.77Hz timing requires an EDID that
# advertises a higher pixel clock (483.33 MHz at the DTD#1 offset).
#
# Without this override, the kernel sees only the panel's stock 60Hz EDID and
# caps the refresh rate at 60Hz even though the HDMI cable + panel can do
# higher refresh rates.
#
# History (2026-08-07):
#   - The override was previously loaded manually via:
#       sudo dd if=/home/luna/nixos/firmware/edid/aoc-AG344UXM-100hz.bin \
#              of=/sys/kernel/debug/dri/0000:c5:00.0/HDMI-A-1/edid_override
#       echo 1 | sudo tee /sys/kernel/debug/dri/0000:c5:00.0/HDMI-A-1/trigger_hotplug
#   - This was fragile: the manual step was easy to forget after a reboot,
#     and the EDID file on disk could drift from what was actually loaded
#     in /sys. Worse, an EDID with a corrupted extension-block checksum once
#     crashed the kernel via `trigger_hpd_mst_set` in the amdgpu module.
#
# This module makes the override declarative:
#   1. Bundles the EDID binary into the nix store (via runCommand, since
#      builtins.readFile rejects binary data with null bytes)
#   2. Provides a systemd oneshot service that runs once per boot
#   3. Service only activates if the debugfs override node exists (skip on
#      hosts without the AOC, e.g. a server-only deployment of this config)
#   4. Service writes the EDID via `dd` (synchronous, exact-size, single-shot)
#   5. Service verifies the write succeeded by comparing md5sums before
#      triggering the per-connector hotplug. If the write fails (EINVAL or
#      kernel rejection), the unit fails and hotplug is NOT triggered — this
#      prevents the kernel oops seen in the 2026-08-07 incident.
#   6. Hotplug trigger uses the per-connector node (HDMI-A-1/trigger_hotplug),
#      NOT the central amdgpu_dm_trigger_hpd_mst (which is what oops'd before).
#
# Usage: import this file from hosts/<host>/default.nix as part of the
# `modules = [ ... ]` list. Currently imported by hosts/UwU-Server/default.nix.
#
# Scope:
#   - Bound to UwU-Server (kernel PCI addr 0000:c5:00.0 + Greetd session that
#     drives the AOC). UwU host config has a different GPU (NVIDIA,
#     0000:0b:00.0) and a different EDID path; if you ever attach an AOC
#     to UwU, copy the binary and adjust the path variables below.
{ config, lib, pkgs, ... }:

let
  # The EDID binary lives in firmware/edid/ at the repo root. We need to copy
  # it into the nix store rather than readFile'ing (readFile rejects null bytes).
  edidPackage = pkgs.runCommand "aoc-AG344UXM-edid" {} ''
    mkdir -p $out
    cp ${../../firmware/edid/aoc-AG344UXM-100hz.bin} $out/aoc-AG344UXM-100hz.bin
    chmod 0444 $out/aoc-AG344UXM-100hz.bin
  '';

  edidStorePath = "${edidPackage}/aoc-AG344UXM-100hz.bin";

  connectorPath = "/sys/kernel/debug/dri/0000:c5:00.0/HDMI-A-1";
  overrideNode  = "${connectorPath}/edid_override";
  hotplugNode   = "${connectorPath}/trigger_hotplug";
in
{
  # Top-level NixOS options — when this file is imported into a NixOS
  # configuration's `modules` list, these get merged in directly.
  systemd.services.aoc-edid-override = {
    description = "AOC AG344UXM EDID override (pruned SVD list, no phantom 4K modes)";
    wantedBy = [ "multi-user.target" ];
    after    = [ "greetd.service" "systemd-modules-load.service" ];

    # Skip silently if the connector or override node doesn't exist
    # (e.g. running on a host without the AOC, or kernel debugfs disabled).
    unitConfig.ConditionPathExists = overrideNode;

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;

      # The override node is root-only (debugfs 0600), and dd needs to write
      # exactly 256 bytes. Use writeShellScriptBin + Environment to ensure
      # coreutils (dd, md5sum, cut, cp) are on PATH. writeShellScript alone
      # produces a script whose PATH is bare and can't find coreutils.
      ExecStart = let
        script = pkgs.writeShellScriptBin "apply-aoc-edid-override" ''
          set -euo pipefail

          EDID_SRC="${edidStorePath}"
          OVERRIDE="${overrideNode}"
          HOTPLUG="${hotplugNode}"

          if [ ! -f "$EDID_SRC" ]; then
            echo "EDID source not found at $EDID_SRC" >&2
            exit 1
          fi
          if [ ! -w "$OVERRIDE" ]; then
            echo "Override node $OVERRIDE not writable (check debugfs mount)" >&2
            exit 1
          fi

          # Snapshot the current override (forensics if anything goes wrong)
          cp "$OVERRIDE" "''${OVERRIDE}.pre-aoc.bak" 2>/dev/null || true

          # Write the EDID. dd is synchronous: returns nonzero on EINVAL.
          # Note: NO fdatasync — debugfs is RAM-backed and fsync returns
          # EINVAL on it. The data is written as soon as dd completes.
          if ! dd if="$EDID_SRC" of="$OVERRIDE" bs=256 count=1 conv=notrunc; then
            echo "dd to override node failed (likely kernel rejected EDID)" >&2
            exit 1
          fi

          # Verify the write landed correctly before triggering anything.
          SRC_MD5=$(md5sum "$EDID_SRC" | cut -d' ' -f1)
          WRITTEN_MD5=$(md5sum "$OVERRIDE" | cut -d' ' -f1)
          if [ "$WRITTEN_MD5" != "$SRC_MD5" ]; then
            echo "Post-write md5 mismatch: got $WRITTEN_MD5, expected $SRC_MD5" >&2
            echo "Restoring previous override to keep the system in a known state" >&2
            if [ -f "''${OVERRIDE}.pre-aoc.bak" ]; then
              cp "''${OVERRIDE}.pre-aoc.bak" "$OVERRIDE" || true
            fi
            exit 1
          fi

          echo "EDID override written and verified (md5=$WRITTEN_MD5)"

          # Trigger per-connector hotplug. CRITICAL: do NOT use
          # amdgpu_dm_trigger_hpd_mst — that path crashed the kernel with a
          # NULL pointer dereference when the override's extension-block
          # checksum was inconsistent (2026-08-07 incident).
          if [ -w "$HOTPLUG" ]; then
            echo 1 > "$HOTPLUG" || echo "trigger_hotplug write failed; not fatal" >&2
          else
            echo "hotplug node $HOTPLUG not writable; override loaded but no mode refresh" >&2
          fi

          echo "AOC EDID override applied successfully"
        '';
      in "${script}/bin/apply-aoc-edid-override";

      # Service hardening — the unit runs as root briefly to write to
      # debugfs. Keep it short-lived; it shouldn't run for more than a few
      # seconds. Protect the rest of the system from a buggy script.
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ connectorPath ];
      NoNewPrivileges = true;
      RestrictSUIDSGID = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;

      # Don't let a stuck service block boot indefinitely
      TimeoutStartSec = "30s";
    };
  };
}