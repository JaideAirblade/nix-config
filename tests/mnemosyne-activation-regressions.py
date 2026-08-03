#!/usr/bin/env python3
"""Regression checks for the Mnemosyne activation snippet."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "modules/ai/mnemosyne.nix"
text = MODULE.read_text()

match = re.search(
    r"system\.activationScripts\.mnemosyne-plugin\s*=\s*''(.*?)\n\s*'';",
    text,
    re.DOTALL,
)
if not match:
    raise SystemExit("FAIL: Mnemosyne activation snippet not found")

snippet = match.group(1)
if re.search(r"^\s*exit(?:\s|$)", snippet, re.MULTILINE):
    raise SystemExit(
        "FAIL: Mnemosyne activation snippet exits the shared NixOS activation script"
    )
if "else" not in snippet:
    raise SystemExit("FAIL: first-install skip is not scoped to the Mnemosyne snippet")

print("mnemosyne activation regressions: PASS")
