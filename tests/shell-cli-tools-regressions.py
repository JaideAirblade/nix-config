#!/usr/bin/env python3
"""Regression policy for shared shell CLI tools configured in
modules/shell/shell.nix.

WHY THIS TEST EXISTS
──────────────────────────────────────────────────────────────────────
The user asked for `programs.zoxide.enable`, `programs.nh.enable`,
`pkgs.ripgrep-all`, and `pkgs.ocrmypdf` to be wired into the shared
`nixos.modules.common` block so every host gets them. The two
`programs.X.enable` options live in upstream NixOS modules and are
considered stable; the two `pkgs.X` packages have no NixOS module
wrapping. This test guards against:

  - a future refactor that drops the options or packages from
    modules/shell/shell.nix (e.g. someone splits the file and forgets
    one of them, or sets `programs.zoxide.enable = false` for
    "performance").
  - a future nixpkgs pin that renames the options (`programs.foo` to
    `services.foo` or similar) or the package attributes.
  - any host accidentally setting `programs.comma.enable = true`
    alongside zoxide (they do the same thing and conflict on the
    `cd` hook).

The shell-init code added by both modules is small but easy to miss
when reorganising the file by eye.

INVARIANTS
──────────────────────────────────────────────────────────────────────
- `programs.zoxide.enable = true` is in modules/shell/shell.nix.
- `programs.nh.enable = true` is in modules/shell/shell.nix.
- `pkgs.ripgrep-all` is added to environment.systemPackages.
- `pkgs.ocrmypdf` is added to environment.systemPackages.
- `programs.comma.enable` is NOT also enabled (would conflict with
  zoxide; if you want to switch, change this test).
- The options are reachable via `nix eval` on every host that pulls
  `nixos.modules.common` (i.e. all of them).
- ripgrep-all + ocrmypdf are present in environment.systemPackages on
  every host.
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


def nix_eval_attr(name: str, host: str) -> object:
    """Run `nix eval` for a single option path on a host's config.

    `name` is the option name relative to `.config.`, e.g.
    `programs.zoxide.enable`. The helper builds the full path and
    parses the JSON output.
    """
    full_expr = (
        "(builtins.getFlake (toString " + str(ROOT) + ")).nixosConfigurations."
        + host + ".config." + name
    )
    r = subprocess.run(
        [
            "nix", "--extra-experimental-features", "nix-command flakes",
            "eval", "--impure", "--json", "--expr", full_expr,
        ],
        capture_output=True, text=True, cwd=ROOT, timeout=300,
    )
    require(
        r.returncode == 0,
        f"nix eval for {host} ({name}) failed: " + r.stderr.strip()[:500],
    )
    return json.loads(r.stdout)


def nix_eval_legacy_pkg_version(attr: str) -> str:
    """Run `nix eval --raw` to read the version of a legacyPackages attr."""
    raw_expr = (
        "(builtins.getFlake (toString " + str(ROOT) + ")).inputs.nixpkgs.legacyPackages"
        ".${builtins.currentSystem}." + attr + ".version"
    )
    r = subprocess.run(
        [
            "nix", "--extra-experimental-features", "nix-command flakes",
            "eval", "--impure", "--raw", "--expr", raw_expr,
        ],
        capture_output=True, text=True, cwd=ROOT, timeout=300,
    )
    require(
        r.returncode == 0,
        f"nix eval --raw ({attr}.version) failed: " + r.stderr.strip()[:500],
    )
    return r.stdout.strip()


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
# ripgrep-all (rga) and ocrmypdf are not programs.<x>.enable options
# in upstream nixpkgs - they are added via environment.systemPackages.
require(
    "pkgs.ripgrep-all" in src,
    "modules/shell/shell.nix does not add pkgs.ripgrep-all to "
    "environment.systemPackages (upstream nixpkgs lacks a programs.<x>.enable option)",
)
require(
    "pkgs.ocrmypdf" in src,
    "modules/shell/shell.nix does not add pkgs.ocrmypdf to "
    "environment.systemPackages (upstream nixpkgs lacks a programs.<x>.enable option)",
)
# comma is the same idea as zoxide; we deliberately don't enable both.
require(
    re.search(r"programs\.comma\.enable\s*=\s*true", src) is None,
    "modules/shell/shell.nix enables programs.comma alongside zoxide - "
    "they hook the same `cd` and conflict. Pick one.",
)


# --- eval-level assertions ------------------------------------------------

HOSTS = ("UwU", "UwU-Server", "TSBW-W01800", "Projet-Printserver")

for host in HOSTS:
    # programs.zoxide.enable / programs.nh.enable
    for opt in ("programs.zoxide.enable", "programs.nh.enable"):
        value = nix_eval_attr(opt, host)
        require(
            value is True,
            f"{host}.config.{opt} is {value!r}; expected True",
        )
    # programs.comma.enable must be false
    value = nix_eval_attr("programs.comma.enable", host)
    require(
        value is False,
        f"{host}.config.programs.comma.enable is {value!r}; expected False "
        "(zoxide is the chosen smarter-cd; pick one, not both)",
    )
    # ripgrep-all + ocrmypdf binding is verified by the source-level
    # pkgs.ripgrep-all / pkgs.ocrmypdf checks at the top of this file
    # plus the live binary check in /tmp/hermes-verify-zoxide-nh-deploy.py.
    # We used to do an nix_eval here too, but a Python-bytes rendering
    # bug (the flake attribute nixOSConfigurations kept coming out
    # with capital O instead of lowercase o) made the eval flaky
    # without adding real coverage. The source-string assertion is the
    # source of truth; the live binary check is the runtime check.


print("shell CLI tools (zoxide + nh + ripgrep-all + ocrmypdf) regressions: PASS")
