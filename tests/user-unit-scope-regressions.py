#!/usr/bin/env python3
"""Ensure desktop/cloud user units never run for Luna or service accounts."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

EXPECTED = {
    "modules/cloud/gdrive-sync.nix": [
        "systemd.user.services.rclone-gdrive-sync",
        "systemd.user.timers.rclone-gdrive-sync",
    ],
    "modules/theming/millennium-theme.nix": [
        "systemd.user.services.millennium-theme-sync",
        "systemd.user.paths.millennium-theme-sync",
    ],
    "modules/theming/readest-dms-theme.nix": [
        "systemd.user.services.readest-dms-theme-sync",
        "systemd.user.paths.readest-dms-theme-sync",
    ],
    "modules/theming/legcord-dms-theme.nix": [
        "systemd.user.services.legcord-dms-theme-sync",
        "systemd.user.paths.legcord-dms-theme-sync",
    ],
    "hosts/UwU/packages/flatpak.nix": [
        "systemd.user.services.sober-flatpak-input-override",
    ],
}


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


for relative, units in EXPECTED.items():
    lines = (ROOT / relative).read_text(encoding="utf-8").splitlines()
    for unit in units:
        start = next((i for i, line in enumerate(lines) if unit in line and "=" in line), -1)
        if start < 0:
            fail(f"missing expected user unit {unit} in {relative}")
        following = "\n".join(lines[start : start + 18])
        if 'ConditionUser = "jaide";' not in following:
            fail(f"{unit} is not scoped to Jaide and can run as Luna")

print("user unit scope regressions: PASS")
