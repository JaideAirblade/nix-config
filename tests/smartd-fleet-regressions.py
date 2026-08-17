#!/usr/bin/env python3
"""Regression tests for the smartd fleet-wide module.

`modules/maintenance/smartd.nix` is the new shared module that
replaces the previously-TSBW-only `services.smartd` block in
`hosts/TSBW-W01800/packages/disk-recovery.nix`. The fleet-wide
version must:

  1. Contribute to `nixos.modules.common` so every host opts in.
  2. Enable `services.smartd` with autodetect (so unknown disks are
     picked up automatically without manual config).
  3. Set the recommended SMART attribute flags:
       -a         monitor all attributes
       -o on      automatic offline testing
       -S on      attribute autosave
       -n standby skip drives in standby (saves laptop battery)
  4. Include a temperature warning threshold (lower than the
     45°C NVMe spec to catch thermal throttling early on the
     Beelink, which runs warm).
  5. Enable wall notifications so logged-in users see SMART failures
     immediately (workstations + TSBW) — server-only mail alerting
     can be added per-host.
  6. NOT duplicate the smartd config — TSBW's old
     `services.smartd = {...}` block in disk-recovery.nix must have
     been removed.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SMARTD_MODULE = ROOT / "modules" / "maintenance" / "smartd.nix"
TSBW_DISK_RECOVERY = ROOT / "hosts" / "TSBW-W01800" / "packages" / "disk-recovery.nix"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(SMARTD_MODULE.exists(), "modules/maintenance/smartd.nix is missing")
require(TSBW_DISK_RECOVERY.exists(),
        "hosts/TSBW-W01800/packages/disk-recovery.nix is missing (expected to be migrated, not deleted)")

shared = SMARTD_MODULE.read_text(encoding="utf-8")
tsbw = TSBW_DISK_RECOVERY.read_text(encoding="utf-8")

# 1. Dendritic target — maintenance (smartd lives in this role; every
# host opts in via nixos.modules.maintenance).
require("nixos.modules.maintenance" in shared,
        "module must contribute to nixos.modules.maintenance")

# 2. Enable + autodetect.
require("services.smartd" in shared,
        "module must configure services.smartd")
require("enable = true" in shared,
        "smartd must be enabled")
require("autodetect = true" in shared,
        "smartd must autodetect drives")

# 3. Recommended flags.
m = re.search(r'defaults\.autodetected\s*=\s*"([^"]+)"', shared)
assert m is not None  # require() above already exited
defaults_block = m.group(1)
require("-a" in defaults_block,
        "smartd must include '-a' (monitor all attributes)")
require("-o on" in defaults_block,
        "smartd must include '-o on' (offline testing)")
require("-S on" in defaults_block,
        "smartd must include '-S on' (attribute autosave)")
require("-n standby" in defaults_block,
        "smartd must include '-n standby' (skip sleeping drives — saves laptop battery)")

# 4. Temperature warning threshold.
require("-W" in defaults_block,
        "smartd must include '-W' temperature threshold")
# Format is `-W <delta>,<low>,<high>` (e.g. `-W 4,35,40`).
w_match = re.search(r"-W\s+(\d+),(\d+),(\d+)", defaults_block)
assert w_match is not None  # require() above already exited
_, low_c, high_c = (int(x) for x in w_match.groups())
require(high_c <= 40,
        f"smartd temperature warning high threshold must be ≤40°C (Beelink runs warm); got {high_c}°C")
require(low_c >= 30,
        f"smartd temperature warning low threshold must be ≥30°C (to avoid noise in winter); got {low_c}°C")

# 5. Wall notifications.
require("notifications.wall.enable" in shared,
        "smartd must enable wall notifications (workstations)")

# 6. No duplicate — TSBW's old block must be gone.
old_block = 'services.smartd = {\n        enable = true;\n        autodetect = true;'
require(old_block not in tsbw,
        "TSBW disk-recovery.nix must no longer declare services.smartd (moved to modules/maintenance/smartd.nix)")

print("modules/maintenance/smartd.nix (fleet-wide smartd, TSBW dedup): PASS")