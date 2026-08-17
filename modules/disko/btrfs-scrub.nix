# btrfs scrub — monthly integrity check for btrfs filesystems.
#
# btrfs scrub reads every block on every btrfs filesystem, recomputes
# checksums, and either fixes mismatches from a spare-device pool
# (single-device: marks the bad block for re-allocation on next write)
# or logs an unrepairable error. Without periodic scrubbing, silent
# bitrot on a multi-TB data pool goes undetected until something tries
# to read the corrupted block and fails.
#
# Cadence: monthly. This is "good enough" for at-rest media pools —
# the more often you scrub, the sooner you catch errors, but monthly
# keeps IO pressure low (a 4 TB scrub takes several hours).
#
# Scope: this module is applied to `nixos.modules.disk`, which only
# UwU and UwU-Server opt into (see hosts/UwU/default.nix:19,
# hosts/UwU-Server/default.nix:30). Printserver, LaptopAP, and TSBW
# don't use btrfs.
#
# What gets scrubbed:
#   - `/` if it's btrfs (UwU has btrfs root; UwU-Server does not — root
#     is ext4 there)
#   - Any mounted btrfs subvolume under /home, /nix, /var, /media
#
# We deliberately do NOT recurse into the data-pool mounts under
# /media/{l1,l2,games,backup} as separate targets — btrfs scrub walks
# the whole device, so listing `/` covers everything on the same fs, and
# per-mount iteration covers the independent pools.
#
# Limitation: there is no upstream NixOS module for `btrfs scrub`
# (only `btrfs.autoScrub` for the root filesystem, which is a different
# service). So this is hand-rolled.
#
# Follows the same shape as `modules/disko/btrfs-dedup.nix`: function
# takes `{ pkgs, ... }:` (no `config` arg), and contributes config
# only. This matches what flake-parts evaluates correctly at flake-time.
_:
{
  nixos.modules.disk =
    { pkgs, ... }:

    {
      environment.systemPackages = [ pkgs.btrfs-progs ];

      systemd.services.btrfs-scrub = {
        description = "btrfs scrub — verify checksums on all mounted btrfs filesystems";
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "btrfs-scrub";
          Nice = 19; # low priority — don't compete with user IO
          IOSchedulingClass = "idle";
          ExecStart = pkgs.writeShellScript "btrfs-scrub" ''
            set -uo pipefail
            # Find every mounted btrfs filesystem, deduplicated by
            # device. /proc/mounts has lines like:
            #   /dev/sda2 /home btrfs rw,relatime,space_cache 0 0
            # We want unique device names only.
            mapfile -t devices < <(
              ${pkgs.util-linux}/bin/findmnt -n -o SOURCE -t btrfs \
                | sort -u
            )

            if [ "''${#devices[@]}" -eq 0 ]; then
              echo "btrfs-scrub: no btrfs filesystems mounted — nothing to do"
              exit 0
            fi

            failed=0
            for dev in "''${devices[@]}"; do
              echo "btrfs-scrub: scrubbing $dev"
              if ! ${pkgs.btrfs-progs}/bin/btrfs scrub start -B "$dev"; then
                echo "btrfs-scrub: FAILED on $dev"
                failed=1
                continue
              fi
              # Print the post-scrub summary (errors found, corrected
              # via spare pool, etc.) into the journal.
              ${pkgs.btrfs-progs}/bin/btrfs device stats "$dev" 2>/dev/null \
                || echo "btrfs-scrub: device stats unavailable for $dev"
            done

            if [ "$failed" -ne 0 ]; then
              echo "btrfs-scrub: one or more scrubs failed — check journal"
              exit 1
            fi
            echo "btrfs-scrub: all filesystems clean"
          '';
        };
      };

      systemd.timers.btrfs-scrub = {
        description = "Monthly btrfs integrity scrub";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          # First Sunday of each month at 5am. Picks the first Sunday
          # so it doesn't conflict with the dedup timer (Sun 04:00)
          # which runs weekly. Spaced an hour apart so they don't
          # overlap if dedup is slow.
          OnCalendar = "Sun *-*-1..7 05:00";
          Persistent = true; # run if missed (e.g. machine was off)
          RandomizedDelaySec = "1h"; # stagger to avoid thundering herd
        };
      };
    }
  ;
}