#!/usr/bin/env python3
"""Regression policy for shared shell CLI tools configured in
modules/shell/shell.nix.

WHY THIS TEST EXISTS
──────────────────────────────────────────────────────────────────────
The user asked for `programs.zoxide.enable` and `programs.nh.enable` to
be wired into the shared `nixos.modules.common` block so every host
gets them. Both options live in upstream NixOS modules and are
considered stable. This test guards against:

  - a future refactor that drops the options from modules/shell/shell.nix
    (e.g. someone splits the file and forgets one of them, or sets
    `programs.zoxide.enable = false` for "performance").
  - a future nixpkgs pin that renames the options (`programs.foo` →
    `services.foo` or similar).
  - any host accidentally setting `programs.comma.enable = true` alongside
    zoxide (they do the same thing and conflict on the `cd` hook).

The shell-init code added by both modules is small but easy to miss
when reorganising the file by eye.

INVARIANTS
──────────────────────────────────────────────────────────────────────
- `programs.zoxide.enable = true` is in modules/shell/shell.nix.
- `programs.nh.enable = true` is in modules/shell/shell.nix.
- `programs.comma.enable` is NOT also enabled (would conflict with
  zoxide; if you want to switch, change this test).
- The options are reachable via `nix eval` on every host that pulls
  `nixos.modules.common` (i.e. all of them).
"""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / "modules/shell/shell.nix"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


# --- source-level assertions ------------------------------------------------

require(SHELL.is_file(), "modules/shell/shell.nix is missing")
src = SHELL.read_text()

require(
    re.search(r"programs\.zoxide\.enable\s*=\s*true", src) is not None,
    "modules/shell/shell.nix does not set programs.zoxide.enable = true",
)
require(
    re.search(r"programs\.nh\.enable\s*=\s*true", src) is not None,
    "modules/shell/shell.nix does not set programs.nh.enable = true",
)
# comma is the same idea as zoxide; we deliberately don't enable both.
require(
    re.search(r"programs\.comma\.enable\s*=\s*true", src) is None,
    "modules/shell/shell.nix enables programs.comma alongside zoxide — "
    "they hook the same `cd` and conflict. Pick one.",
)


# --- eval-level assertion ---------------------------------------------------
# Walk every host that pulls common and assert both options are True.
# The set is the same as the userdbd test — all NixOS hosts in the flake.

for host in ("UwU", "UwU-Server", "TSBW-W01800", "Projet-Printserver"):
    for opt in ("programs.zoxide.enable", "programs.nh.enable"):
        r = subprocess.run(
            [
                "nix", "--extra-experimental-features", "nix-command flakes",
                "eval", "--impure", "--json", "--expr",
                f"(builtins.getFlake (toString {ROOT})).nixosConfigurations.{host}.config.{opt}",
            ],
            capture_output=True, text=True, cwd=ROOT, timeout=300,
        )
        require(
            r.returncode == 0,
            f"nix eval for {host} {opt} failed: " + r.stderr.strip()[:500],
        )
        value = json.loads(r.stdout)
        require(
            value is True,
            f"{host}.config.{opt} is {value!r}; expected True",
        )
    # comma must NOT be enabled on any host.
    r = subprocess.run(
        [
            "nix", "--extra-experimental-features", "nix-command flakes",
            "eval", "--impure", "--json", "--expr",
            f"(builtins.getFlake (toString {ROOT})).nixosConfigurations.{host}.config.programs.comma.enable",
        ],
        capture_output=True, text=True, cwd=ROOT, timeout=300,
    )
    require(
        r.returncode == 0,
        f"nix eval for {host} programs.comma.enable failed: " + r.stderr.strip()[:500],
    )
    value = json.loads(r.stdout)
    require(
        value is False,
        f"{host}.config.programs.comma.enable is {value!r}; expected False "
        "(zoxide is the chosen smarter-cd; pick one, not both)",
    )


print("shell CLI tools (zoxide + nh) regressions: PASS")
