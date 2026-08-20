#!/usr/bin/env python3
"""Regression contract for modules/maintenance/heartbeat.nix + umbrella.

Enforces the heartbeat (dead-man's switch) module's shape without
actually running the timer.

What we check:

  1. Both files exist (umbrella + config-only contributor).
  2. The umbrella (modules/maintenance/default.nix) declares options
     under `maintenance.heartbeat` — the clean Option A split where
     options live in one file and config lives in another (mirrors
     disko.nix + btrfs-dedup.nix).
  3. The heartbeat.nix file is CONFIG-ONLY — it does NOT take a
     `config` argument (flake-parts evaluates deferred modules at
     flake-time without `config`/`pkgs` in scope).
  4. systemd service `heartbeat` (oneshot) reads the Uptime Kuma push
     URL from a sops-rendered file at /run/secrets/heartbeat-endpoint
     and uses curl HEAD.
  5. The service gracefully no-ops if the sops file is missing
     (exits 0 with a journal message) — supports a host deployed
     before its secret exists.
  6. systemd timer `heartbeat` exists with Persistent + RandomizedDelaySec
     + wantedBy = [ "timers.target" ].
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HEARTBEAT = ROOT / "modules" / "maintenance" / "heartbeat.nix"
UMBRELLA = ROOT / "modules" / "maintenance" / "options.nix"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(HEARTBEAT.exists(), "modules/maintenance/heartbeat.nix is missing")
require(UMBRELLA.exists(),
        "modules/maintenance/default.nix is missing (umbrella for option declarations)")

src = HEARTBEAT.read_text(encoding="utf-8")
umbrella_src = UMBRELLA.read_text(encoding="utf-8")

# 1. Dendritic contribution target.
require("nixos.modules.maintenance" in src,
        "module must contribute to nixos.modules.maintenance (the role)")

# 2. Options live in the umbrella.
require("options.maintenance.heartbeat" in umbrella_src,
        "umbrella must declare options.maintenance.heartbeat")
for needle in ("enable", "sopsKey", "intervalSeconds"):
    require(needle in umbrella_src,
            f"umbrella must declare option '{needle}' under maintenance.heartbeat")
require("mkEnableOption" in umbrella_src,
        "umbrella must use mkEnableOption for the enable option")

# 3. Config-only file — function takes only flake-parts-safe args.
# Look for the first function signature line.
sig_match = re.search(r"\{[^}]*\}:", src)
assert sig_match is not None  # require() above already exited
sig = sig_match.group(0)
for forbidden in ("config,", "config ", "{config"):
    require(forbidden not in sig,
            f"module function must NOT take `{forbidden}` as arg (flake-parts doesn't provide it at flake-time)")
# `pkgs` and `lib` are both safe (flake-parts provides lib; pkgs is
# only used inside the script body, which NixOS instantiates lazily).

# 4. systemd service behaviour.
require("systemd.services.heartbeat" in src,
        "module must declare systemd.services.heartbeat")
require('Type = "oneshot";' in src,
        "service must be oneshot (not simple)")
require("/run/secrets/heartbeat-endpoint" in src,
        "service must read the URL from /run/secrets/heartbeat-endpoint (sops-rendered file)")
require("curl" in src,
        "service must use curl")
require("-X HEAD" in src or "--head" in src,
        "service must use HEAD request (cheapest method for Uptime Kuma push)")
require("&msg=" in src,
        "service must rewrite/append &msg=<timestamp> so Uptime Kuma heartbeat panel shows per-ping identity")

# 5. Missing-secret handling — the script must not fail if the sops
# file doesn't exist yet (e.g. host deployed before secret was
# generated). Exit 0 + journal message is the right behaviour.
require("exit 0" in src and "skipping ping" in src.lower(),
        "service must exit 0 (not fatal) when sops secret is missing")

# 6. systemd timer.
require("systemd.timers.heartbeat" in src,
        "module must declare systemd.timers.heartbeat")
require("OnUnitActiveSec" in src,
        "timer must use OnUnitActiveSec (interval-driven)")
require('Persistent = true' in src,
        "timer must be Persistent")
require('RandomizedDelaySec' in src,
        "timer must include RandomizedDelaySec to spread fleet pings")
require('"timers.target"' in src,
        "timer must be wantedBy timers.target")

print("modules/maintenance/heartbeat.nix (Uptime Kuma push, missing-secret fallback, Option A split): PASS")