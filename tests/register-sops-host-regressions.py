#!/usr/bin/env python3
"""Behavioral regression tests for scripts/register-sops-host.py."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts" / "register-sops-host.py"
PUBKEY = "age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqp5ks3"
BASE = """\
keys:
  - &admin age1admin
  - &host_existing age1existing

creation_rules:
  - path_regex: secrets/existing/.*\\.yaml$
    key_groups:
      - age:
          - *admin
          - *host_existing

  - path_regex: secrets/shared/.*\\.yaml$
    key_groups:
      - age:
          - *admin
          - *host_existing

  - path_regex: secrets\\.yaml$
    key_groups:
      - age:
          - *admin
          - *host_existing
"""


def run_helper(path: Path, host: str = "new-host") -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(HELPER), str(path), host, PUBKEY],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        rules = Path(tmp) / ".sops.yaml"
        rules.write_text(BASE)

        first = run_helper(rules)
        if first.returncode != 0:
            raise SystemExit(f"FAIL: first registration failed: {first.stderr or first.stdout}")

        content = rules.read_text()
        expected_anchor = f"  - &host_new-host {PUBKEY}"
        if content.count(expected_anchor) != 1:
            raise SystemExit("FAIL: host key anchor was not added exactly once")

        host_rule = """\
  - path_regex: secrets/new-host/.*\\.yaml$
    key_groups:
      - age:
          - *admin
          - *host_new-host
"""
        if host_rule not in content:
            raise SystemExit("FAIL: a per-host creation rule was not created")

        for rule_name in ("secrets/shared/.*\\.yaml$", "secrets\\.yaml$"):
            start = content.index(f"  - path_regex: {rule_name}")
            end = content.find("\n  - path_regex:", start + 1)
            block = content[start:] if end == -1 else content[start:end]
            if block.count("          - *host_new-host") != 1:
                raise SystemExit(f"FAIL: host reference missing/duplicated in {rule_name}")

        second = run_helper(rules)
        if second.returncode != 0:
            raise SystemExit(f"FAIL: idempotent registration failed: {second.stderr or second.stdout}")
        if rules.read_text() != content:
            raise SystemExit("FAIL: second registration was not idempotent")

        invalid = run_helper(rules, "bad host")
        if invalid.returncode == 0:
            raise SystemExit("FAIL: unsafe hostname was accepted")

    print("register-sops-host regressions: PASS")


if __name__ == "__main__":
    main()
