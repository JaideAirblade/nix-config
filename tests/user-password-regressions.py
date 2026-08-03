#!/usr/bin/env python3
"""Prevent plaintext bootstrap passwords from entering the Nix store."""

from pathlib import Path

root = Path(__file__).resolve().parents[1]
violations: list[str] = []
for path in root.glob("**/*.nix"):
    text = path.read_text()
    if "initialPassword" in text:
        violations.append(str(path.relative_to(root)))

if violations:
    raise SystemExit("FAIL: plaintext initialPassword appears in: " + ", ".join(violations))

print("user password regressions: PASS")
