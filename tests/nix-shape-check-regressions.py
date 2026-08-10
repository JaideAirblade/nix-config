#!/usr/bin/env python3
"""
Regression test for scripts/nix-shape-check.sh.

Strategy: create a temporary mini-flake with fixtures that exercise each
of the 5 rules, then run the shape-checker against it. Assert that:
  - Each rule's positive case is caught (error or warn as appropriate)
  - Each rule's negative case is NOT caught (the checker doesn't false-positive)
  - The current ~/nixos tree's two known shape issues are detected
    (so we don't silently regress the checker)
  - Exit codes match the documented contract (0 = clean, 1 = errors, 2 = usage)

This is a pure-stdlib test (no PyYAML, no NixOS python deps).
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path("/home/luna/nixos")
CHECKER = REPO_ROOT / "scripts" / "nix-shape-check.sh"


# ── Mini-flake fixture builder ─────────────────────────────────────

def make_fixture(root: Path) -> None:
    """Create a tiny flake layout that exercises every rule + the
    corresponding "good" cases (rules must not false-positive)."""
    # Layout:
    #   flake.nix            (with dendriticExceptions)
    #   hosts/HostA/
    #     default.nix        (entry point — must NOT trigger orphan)
    #     good-host.nix      (correct shape — nixos.hosts."HostA")
    #     bad-pattern.nix    (declares nixos.modules.common — pattern mismatch)
    #     wrong-hostname.nix (declares nixos.hosts."HostB" — hostname mismatch)
    #     missing-pkgs.nix   (uses pkgs.bar but no pkgs in inner args)
    #     orphan.nix         (bare NixOS module, not excepted, not imported)
    #   modules/foo/
    #     good.nix           (correct shape — nixos.modules.common)
    #     collision.nix      (two environment.systemPackages — collision)
    #     role-bad.nix       (declares nixos.hosts."HostA" — role pattern mismatch)
    (root / "hosts" / "HostA").mkdir(parents=True)
    (root / "modules" / "foo").mkdir(parents=True)

    (root / "flake.nix").write_text(
        '{\n'
        '  dendriticExceptions = {\n'
        '    "hosts/HostA/excused.nix" = "test exception";\n'
        '  };\n'
        '  collectModules = root: prefix: [];\n'
        '}\n'
    )

    (root / "hosts" / "HostA" / "default.nix").write_text(
        '{ config, inputs, ... }:\n'
        '{\n'
        '  flake.nixosConfigurations.HostA = inputs.nixpkgs.lib.nixosSystem {\n'
        '    modules = [ ./good-host ./excused ];\n'
        '  };\n'
        '}\n'
    )

    (root / "hosts" / "HostA" / "good-host.nix").write_text(
        '{ inputs, ... }:\n'
        '{\n'
        '  nixos.hosts."HostA" =\n'
        '    { config, pkgs, lib, ... }:\n'
        '    {\n'
        '      programs.foo.enable = true;\n'
        '    };\n'
        '}\n'
    )

    # PATTERN MISMATCH: host file declaring role
    (root / "hosts" / "HostA" / "bad-pattern.nix").write_text(
        '{ inputs, ... }:\n'
        '{\n'
        '  nixos.modules.common =\n'
        '    { lib, pkgs, ... }:\n'
        '    {\n'
        '      programs.foo.enable = true;\n'
        '    };\n'
        '}\n'
    )

    # HOSTNAME MISMATCH: declares HostB in hosts/HostA/
    (root / "hosts" / "HostA" / "wrong-hostname.nix").write_text(
        '{ inputs, ... }:\n'
        '{\n'
        '  nixos.hosts."HostB" =\n'
        '    { config, pkgs, lib, ... }:\n'
        '    {\n'
        '      programs.foo.enable = true;\n'
        '    };\n'
        '}\n'
    )

    # INNER ARGS MISSING: pkgs used, not declared
    (root / "hosts" / "HostA" / "missing-pkgs.nix").write_text(
        '{ inputs, ... }:\n'
        '{\n'
        '  nixos.hosts."HostA" =\n'
        '    { config, lib, ... }:\n'
        '    {\n'
        '      environment.systemPackages = [ pkgs.bar ];\n'
        '    };\n'
        '}\n'
    )

    # ORPHAN: bare NixOS module not excepted, not imported
    (root / "hosts" / "HostA" / "orphan.nix").write_text(
        '{ config, pkgs, lib, ... }:\n'
        '{\n'
        '  programs.orphan.enable = true;\n'
        '}\n'
    )

    # GOOD — nixos.modules.common with proper pkgs
    (root / "modules" / "foo" / "good.nix").write_text(
        '{ inputs, ... }:\n'
        '{\n'
        '  nixos.modules.common =\n'
        '    { lib, pkgs, ... }:\n'
        '    {\n'
        '      programs.baz.enable = true;\n'
        '    };\n'
        '}\n'
    )

    # ATTRSET COLLISION: two environment.systemPackages in same file
    (root / "modules" / "foo" / "collision.nix").write_text(
        '{ inputs, ... }:\n'
        '{\n'
        '  nixos.modules.common =\n'
        '    { lib, pkgs, ... }:\n'
        '    {\n'
        '      environment.systemPackages = [ pkgs.a ];\n'
        '      environment.systemPackages = [ pkgs.b ];\n'
        '    };\n'
        '}\n'
    )

    # ROLE PATTERN MISMATCH: shared module declaring a host
    (root / "modules" / "foo" / "role-bad.nix").write_text(
        '{ inputs, ... }:\n'
        '{\n'
        '  nixos.hosts."HostA" =\n'
        '    { config, pkgs, lib, ... }:\n'
        '    {\n'
        '      programs.foo.enable = true;\n'
        '    };\n'
        '}\n'
    )

    # Multi-line inner args with pkgs on its own line (must be detected
    # as having pkgs — sanity for the multi-line signature handling).
    (root / "modules" / "foo" / "multiline-pkgs.nix").write_text(
        '{ inputs, ... }:\n'
        '{\n'
        '  nixos.modules.common =\n'
        '    { lib\n'
        '    , pkgs\n'
        '    , ...\n'
        '    }:\n'
        '    {\n'
        '      programs.quux.enable = true;\n'
        '      environment.systemPackages = [ pkgs.quux ];\n'
        '    };\n'
        '}\n'
    )


# ── Helpers ───────────────────────────────────────────────────────

def run_checker(root: Path, *args: str) -> tuple[int, str, list[dict]]:
    """Run the shape checker against `root`. Returns (exit, stdout_text, json_issues)."""
    proc = subprocess.run(
        [str(CHECKER), *args],
        capture_output=True, text=True, cwd=root,
    )
    # Always also run JSON to get structured issues.
    json_proc = subprocess.run(
        [str(CHECKER), "--json", *args],
        capture_output=True, text=True, cwd=root,
    )
    issues = []
    try:
        data = json.loads(json_proc.stdout)
        issues = data.get("issues", [])
    except json.JSONDecodeError:
        pass
    return proc.returncode, proc.stdout + proc.stderr, issues


def issues_matching(issues: list[dict], rule: str, file_substr: str) -> list[dict]:
    return [i for i in issues if i["rule"] == rule and file_substr in i["file"]]


# ── Test cases ────────────────────────────────────────────────────

def test_each_rule_positive():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        make_fixture(root)
        rc, out, issues = run_checker(root)

        results = []
        # RULE 1 — pattern-mismatch (host file declares role)
        results.append((
            "pattern-mismatch (host file with role decl)",
            bool(issues_matching(issues, "pattern-mismatch", "bad-pattern.nix")),
        ))
        # RULE 1 (other direction) — pattern-mismatch (role file declares host)
        results.append((
            "pattern-mismatch (role file with host decl)",
            bool(issues_matching(issues, "pattern-mismatch", "role-bad.nix")),
        ))
        # RULE 2 — hostname-mismatch
        results.append((
            "hostname-mismatch",
            bool(issues_matching(issues, "hostname-mismatch", "wrong-hostname.nix")),
        ))
        # RULE 3 — inner-args-missing
        results.append((
            "inner-args-missing",
            bool(issues_matching(issues, "inner-args-missing", "missing-pkgs.nix")),
        ))
        # RULE 4 — attrset-collision
        results.append((
            "attrset-collision",
            bool(issues_matching(issues, "attrset-collision", "collision.nix")),
        ))
        # RULE 5 — orphan-module
        results.append((
            "orphan-module",
            bool(issues_matching(issues, "orphan-module", "orphan.nix")),
        ))
        # Negative — good-host.nix (correct shape) must NOT trigger
        # any of the rules.
        good_hits = [
            i for i in issues
            if "good-host.nix" in i["file"]
        ]
        results.append((
            "no false positive on good-host.nix",
            len(good_hits) == 0,
        ))
        # Negative — good.nix (correct shape) must NOT trigger
        good_mod_hits = [
            i for i in issues
            if "modules/foo/good.nix" in i["file"]
        ]
        results.append((
            "no false positive on modules/foo/good.nix",
            len(good_mod_hits) == 0,
        ))
        # Negative — multiline-pkgs.nix (multi-line signature with pkgs
        # on its own line) must NOT trigger inner-args-missing.
        ml_hits = issues_matching(issues, "inner-args-missing", "multiline-pkgs.nix")
        results.append((
            "no false positive on multi-line pkgs signature",
            len(ml_hits) == 0,
        ))
        # Negative — default.nix (host entry point) must NOT trigger orphan.
        def_hits = issues_matching(issues, "orphan-module", "default.nix")
        results.append((
            "no false positive on hosts/<H>/default.nix",
            len(def_hits) == 0,
        ))
        # Exit code must be non-zero (we have errors).
        results.append((
            "exit code 1 when errors present",
            rc == 1,
        ))
        return results


def test_json_output_format():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        make_fixture(root)
        proc = subprocess.run(
            [str(CHECKER), "--json"],
            capture_output=True, text=True, cwd=root,
        )
        results = []
        # JSON must parse.
        try:
            data = json.loads(proc.stdout)
            results.append(("JSON output parses", True))
            results.append((
                "JSON has 'checked' key",
                isinstance(data.get("checked"), int),
            ))
            results.append((
                "JSON has 'issues' array",
                isinstance(data.get("issues"), list),
            ))
            for issue in data.get("issues", []):
                # Each issue must have the documented fields.
                for field in ("severity", "file", "rule", "line", "message"):
                    if field not in issue:
                        results.append((f"issue has '{field}'", False))
                        break
            else:
                results.append(("all issues have required fields", True))
        except json.JSONDecodeError as e:
            results.append(("JSON output parses", False))
            results.append((f"JSON parse error: {e}", False))
        return results


def test_single_file_mode():
    """`./nix-shape-check.sh path/to/file.nix` should check only that file."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        make_fixture(root)
        # Check only the bad-pattern file.
        rc, out, issues = run_checker(root, "hosts/HostA/bad-pattern.nix")
        results = []
        # Should find the pattern-mismatch but NOT other issues.
        results.append((
            "single-file mode catches target file's issue",
            bool(issues_matching(issues, "pattern-mismatch", "bad-pattern.nix")),
        ))
        results.append((
            "single-file mode doesn't report other files' issues",
            not any("collision.nix" in i["file"] for i in issues),
        ))
        return results


def test_clean_tree():
    """A tree with no issues should produce exit 0 and no issues."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "hosts" / "HostA").mkdir(parents=True)
        (root / "modules" / "foo").mkdir(parents=True)
        (root / "flake.nix").write_text(
            '{\n'
            '  dendriticExceptions = {};\n'
            '  collectModules = root: prefix: [];\n'
            '}\n'
        )
        (root / "hosts" / "HostA" / "default.nix").write_text(
            '{ config, inputs, ... }: { flake.nixosConfigurations.HostA = {}; }\n'
        )
        (root / "hosts" / "HostA" / "good.nix").write_text(
            '{ inputs, ... }:\n'
            '{\n'
            '  nixos.hosts."HostA" =\n'
            '    { config, pkgs, lib, ... }: { programs.foo.enable = true; };\n'
            '}\n'
        )
        (root / "modules" / "foo" / "good.nix").write_text(
            '{ inputs, ... }:\n'
            '{\n'
            '  nixos.modules.common =\n'
            '    { lib, pkgs, ... }: { programs.baz.enable = true; };\n'
            '}\n'
        )
        rc, out, issues = run_checker(root)
        results = [
            ("clean tree exits 0", rc == 0),
            ("clean tree has zero issues", len(issues) == 0),
        ]
        return results


def test_current_repo_known_findings():
    """Sanity check: the two known issues in ~/nixos must still be caught."""
    if not (REPO_ROOT / "flake.nix").exists():
        return [("current repo exists", False)]
    rc, out, issues = run_checker(REPO_ROOT)
    results = []
    # Known issue: modules/ai/hermes-mobile-bridge.nix is misplaced
    # (lives under modules/ but declares nixos.hosts."UwU-Server").
    results.append((
        "current repo: pattern-mismatch on hermes-mobile-bridge.nix still caught",
        bool(issues_matching(issues, "pattern-mismatch", "hermes-mobile-bridge.nix")),
    ))
    # Known: modules/users/private-accounts.nix has two
    # environment.systemPackages in same file.
    results.append((
        "current repo: attrset-collision on private-accounts.nix still caught",
        bool(issues_matching(issues, "attrset-collision", "private-accounts.nix")),
    ))
    return results


# ── Runner ─────────────────────────────────────────────────────────

def main() -> int:
    all_results = []

    print("=== test: each rule positive ===")
    for name, ok in test_each_rule_positive():
        mark = "✓" if ok else "✗"
        print(f"  {mark}  {name}")
        all_results.append((name, ok))

    print("\n=== test: JSON output format ===")
    for name, ok in test_json_output_format():
        mark = "✓" if ok else "✗"
        print(f"  {mark}  {name}")
        all_results.append((name, ok))

    print("\n=== test: single-file mode ===")
    for name, ok in test_single_file_mode():
        mark = "✓" if ok else "�"
        print(f"  {mark}  {name}")
        all_results.append((name, ok))

    print("\n=== test: clean tree (no false positives) ===")
    for name, ok in test_clean_tree():
        mark = "✓" if ok else "✗"
        print(f"  {mark}  {name}")
        all_results.append((name, ok))

    print("\n=== test: current repo's known findings still detected ===")
    for name, ok in test_current_repo_known_findings():
        mark = "✓" if ok else "✗"
        print(f"  {mark}  {name}")
        all_results.append((name, ok))

    total = len(all_results)
    passed = sum(1 for _, ok in all_results if ok)
    print(f"\n=== summary: {passed}/{total} passed ===")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
