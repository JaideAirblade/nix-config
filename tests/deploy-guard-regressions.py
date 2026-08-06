#!/usr/bin/env python3
"""Regression test for the deploy-host guard.

This test asserts that every local deploy recipe in the Justfile calls
`scripts/confirm-local-deploy.sh` as its first step. Without that guard,
running `just deploy <wrong-host>` on a machine whose hostname doesn't
match the target would silently apply the wrong host's NixOS config,
breaking users, disk layout, firewall, and services (the 2026-08-06
near-miss).

The deploy-remote* recipes are NOT required to have the guard — their
target is explicit in the recipe name and they push via SSH to a remote
host, so they cannot mistakenly target the local machine.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JUSTFILE = ROOT / "Justfile"
GUARD_SCRIPT = ROOT / "scripts" / "confirm-local-deploy.sh"

results: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    mark = "PASS" if ok else "FAIL"
    suffix = f"  ({detail})" if detail else ""
    print(f"  {mark}  {name}{suffix}")
    results.append((name, ok, detail))


justfile = JUSTFILE.read_text()

# ── The guard script must exist and be executable ─────────────────
check(
    "scripts/confirm-local-deploy.sh exists",
    GUARD_SCRIPT.exists(),
    str(GUARD_SCRIPT),
)
if GUARD_SCRIPT.exists():
    check(
        "scripts/confirm-local-deploy.sh is executable",
        bool(GUARD_SCRIPT.stat().st_mode & 0o111),
        f"mode={oct(GUARD_SCRIPT.stat().st_mode & 0o777)}",
    )


# ── Every LOCAL deploy recipe must call the guard ─────────────────
# Local deploy recipes (these run nixos-rebuild switch on the local
# machine): deploy, debug, up, upp.
LOCAL_DEPLOY_RECIPES = ["deploy", "debug", "up", "upp"]

# Remote deploy recipes (push to a remote host via SSH): deploy-remote,
# dry-remote, bootstrap, provision. These must NOT be required to call
# the local-deploy guard.
REMOTE_DEPLOY_RECIPES = ["deploy-remote", "dry-remote", "bootstrap", "provision"]

# Parse just recipes: find recipe headers and bodies. A recipe header
# in just 1.57 looks like:
#     recipe_name [args]:
#         body line 1
#         body line 2
# Recipe bodies are indented (one tab or more).
#
# We support several header shapes:
#   - `name:`
#   - `name $arg:`
#   - `name $arg=default:`
#   - `name $arg1 $arg2=default:`
recipe_pattern = re.compile(
    r'^([a-zA-Z_][\w-]*)\s+((?:\$\w+(?:=\w+)?\s*)+):\s*\n((?:^[ \t]+.*\n?)*)',
    re.MULTILINE,
)
all_recipes = {}
for match in recipe_pattern.finditer(justfile):
    name = match.group(1)
    body = match.group(3)
    all_recipes[name] = body


for recipe_name in LOCAL_DEPLOY_RECIPES:
    body = all_recipes.get(recipe_name)
    if body is None:
        check(
            f"Justfile defines recipe `{recipe_name}`",
            False,
            f"recipe not found in Justfile",
        )
        continue
    has_guard = "confirm-local-deploy.sh" in body
    check(
        f"local deploy recipe `{recipe_name}` calls confirm-local-deploy.sh",
        has_guard,
        f"body starts with: {body.splitlines()[0].strip()[:60]!r}"
        if not has_guard else "guard present",
    )
    # Also assert the guard is the FIRST command in the body, not
    # somewhere later (a later call could be skipped if the build
    # fails before reaching it).
    if has_guard:
        first_meaningful_line = next(
            (line.strip() for line in body.splitlines() if line.strip()),
            "",
        )
        check(
            f"guard is the first line of `{recipe_name}`",
            "confirm-local-deploy.sh" in first_meaningful_line,
            f"first line: {first_meaningful_line[:80]!r}",
        )


# ── Remote deploy recipes must NOT call the local-deploy guard ────
for recipe_name in REMOTE_DEPLOY_RECIPES:
    body = all_recipes.get(recipe_name, "")
    has_guard = "confirm-local-deploy.sh" in body
    check(
        f"remote recipe `{recipe_name}` does NOT use the local-deploy guard "
        f"(uses deploy-remote flow)",
        not has_guard,
        f"unexpected local guard call in remote recipe"
        if has_guard else "clean",
    )


# ── The guard script content sanity checks ────────────────────────
if GUARD_SCRIPT.exists():
    content = GUARD_SCRIPT.read_text()
    check(
        "guard script checks for hostname mismatch",
        '"$target" != "$cur"' in content or 'target != cur' in content,
        "compares target arg to hostname",
    )
    check(
        "guard script YES-confirmation is only in the MISMATCH branch",
        # The literal "YES" check should exist, but only inside the if-block
        content.count('"$ans" != "YES"') == 1,
        "exactly one YES comparison (only the mismatch branch prompts)",
    )
    check(
        "guard script's MATCH branch proceeds without prompt",
        'matches hostname, proceeding' in content,
        "match-case prints one safe-line and continues",
    )
    check(
        "guard script refuses non-interactive runs (no /dev/tty) on mismatch",
        "/dev/tty" in content,
        "uses /dev/tty so piped stdin cannot auto-confirm",
    )
    check(
        "guard script points user to deploy-remote as the right tool",
        "deploy-remote" in content,
        "remediation hint present",
    )


# ── Summary ───────────────────────────────────────────────────────
passed = sum(1 for _, ok, _ in results if ok)
total = len(results)
print()
print(f"== {passed}/{total} checks passed ==")
if passed != total:
    print("FAIL: deploy-guard regressions")
    for name, ok, detail in results:
        if not ok:
            print(f"  - {name}  {detail}")
    sys.exit(1)
print("deploy-guard regressions: PASS")
