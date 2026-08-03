#!/usr/bin/env python3
"""Regression checks for AD-lab VM names used in destructive paths."""

from pathlib import Path

source = (Path(__file__).resolve().parents[1] / "modules/virtualisation/ad-lab.nix").read_text()

required = {
    "validator": "validateLabClientName",
    "restricted character set": "^ad-[A-Za-z0-9][A-Za-z0-9_-]*$",
    "domain-controller guard": "ad-dc1",
    "client-base guard": "ad-client-base",
}
for label, needle in required.items():
    if needle not in source:
        raise SystemExit(f"FAIL: missing {label}: {needle}")

if source.count("${validateLabClientName}") < 3:
    raise SystemExit("FAIL: fresh/revert/nuke do not all validate VM names")

for unsafe in ("$HOME/.ssh/lab-keys/$VM_NAME",):
    if unsafe in source:
        raise SystemExit(f"FAIL: destructive key path is still built before validation: {unsafe}")

print("AD-lab name regressions: PASS")
