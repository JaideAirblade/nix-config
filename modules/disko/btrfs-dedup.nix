# btrfs deduplication via duperemove.
#
# duperemove scans btrfs filesystems for duplicate data extents and
# submits them for deduplication. On btrfs this is a metadata-only
# operation (no data copying) — it tells the filesystem "these blocks
# are identical, reference them once."
#
# This module installs duperemove + a systemd timer that runs it
# weekly on all mounted btrfs subvolumes.
#
# Only applies to btrfs filesystems — on XFS/ext4 it's a no-op
# (duperemove will just skip or error, which we suppress).
{ pkgs, lib, ... }:

{
  environment.systemPackages = [ pkgs.duperemove ];

  # Weekly deduplication — runs Sunday 4am, low priority
  systemd.services.btrfs-dedup = {
    description = "btrfs deduplication via duperemove";
    serviceConfig = {
      Type = "oneshot";
      # Run duperemove on the key subvolumes. --dedupe=yes actually
      # submits extents for dedup (not just a dry run).
      # -r = recursive, --hashfile = cache hashes between runs (faster)
      ExecStart = pkgs.writeShellScript "btrfs-dedup" ''
        set -e
        for dir in / /nix /home /var; do
          if mountpoint -q "$dir" && ${pkgs.util-linux}/bin/findmnt -n -o FSTYPE "$dir" 2>/dev/null | grep -q btrfs; then
            echo "Deduplicating $dir..."
            ${pkgs.duperemove}/bin/duperemove -dr --dedupe=yes "$dir" 2>&1 || true
          fi
        done
      '';
      # Low priority — don't compete with real work
      IOSchedulingClass = "idle";
      Nice = 19;
    };
  };

  systemd.timers.btrfs-dedup = {
    description = "Weekly btrfs deduplication";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 04:00";
      Persistent = true;  # run if missed (e.g. machine was off)
      RandomizedDelaySec = "30m";  # spread out to avoid spikes
    };
  };
}