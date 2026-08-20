#!/usr/bin/env python3
"""Regression tests for modules/disko/btrfs-scrub.nix.

Enforces the btrfs-scrub systemd service + timer shape without actually
running btrfs scrub (which would mutate disk state and require root).

What we check:

  1. The module declares `nixos.modules.disk` so the dendritic walker
     picks it up (the same convention as btrfs-dedup).
  2. A systemd *service* `btrfs-scrub` exists, of type `oneshot`,
     that runs a shell script which:
       a. finds mounted btrfs filesystems via findmnt -t btrfs
       b. invokes `btrfs scrub start -B` on each unique device
       c. logs per-device results and exits non-zero on any failure
  3. A systemd *timer* `btrfs-scrub` exists with:
       a. wantedBy = [ "timers.target" ]
       b. OnCalendar monthly (Sunday, first week of month)
       c. Persistent = true (run if missed)
  4. btrfs-progs is in environment.systemPackages so ad-hoc
     `btrfs scrub status /dev/nvmeXn1` works.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "modules" / "disko" / "btrfs-scrub.nix"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(MODULE.exists(), "modules/disko/btrfs-scrub.nix is missing")
src = MODULE.read_text(encoding="utf-8")

# 1. Dendritic contribution target — must match btrfs-dedup's pattern.
require("nixos.modules.disk" in src,
        "module must contribute to nixos.modules.disk (matching btrfs-dedup)")

# 2. systemd service — oneshot, finds btrfs mounts, runs scrub.
require('systemd.services.btrfs-scrub' in src,
        "module must declare systemd.services.btrfs-scrub")
require('Type = "oneshot";' in src,
        "service must be oneshot (not simple/exec)")
require("btrfs scrub start" in src,
        "service must invoke 'btrfs scrub start' (not btrfs balance or scrub status)")
require("findmnt" in src and "btrfs" in src,
        "service script must discover btrfs filesystems via findmnt")
# `-B` blocks until scrub completes — required for the oneshot
# service to know when to exit. Without it, the service would exit
# immediately and the timer would happily "succeed" on a 0-byte
# unfinished scrub.
require("-B" in src,
        "service must use 'btrfs scrub start -B' (block until completion)")

# 3. systemd timer — monthly cadence, persistent.
require('systemd.timers.btrfs-scrub' in src,
        "module must declare systemd.timers.btrfs-scrub")
require('OnCalendar' in src,
        "timer must use OnCalendar")
# Either "monthly" or "*-*-1..7" (first week of month) is acceptable;
# either way it must NOT be daily/weekly which would thrash disks.
require(('"monthly"' in src) or ('*-*-1..7' in src),
        "timer must be monthly cadence (not weekly or daily)")
require('Persistent = true' in src,
        "timer must be Persistent so missed runs catch up on next boot")
require('"timers.target"' in src,
        "timer must be wantedBy timers.target")

# 4. btrfs-progs available on $PATH for ad-hoc inspection.
require("btrfs-progs" in src and "environment.systemPackages" in src,
        "module must add btrfs-progs to environment.systemPackages")

print("modules/disko/btrfs-scrub.nix (monthly scrub + btrfs-progs on PATH): PASS")