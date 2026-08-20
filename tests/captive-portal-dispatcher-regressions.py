#!/usr/bin/env python3
"""Regression: captive portal dispatcher must not spam Helium.

Symptom (2026-08-17): Helium was opening "very often" with
`http://1.1.1.1` as the target, even on a wired LAN with no
captive portal. The dispatcher (NetworkManager/dispatcher.d/30-captive-portal.sh)
reacted to BOTH `connectivity-change` AND `up` events, AND to both
`PORTAL` and `LIMITED` states. On a dual-stack host (wired + WiFi
both active) the `up` branch fired on every DHCP renew for
`enp10s0`, opening Helium with `http://1.1.1.1` every few
minutes even when the network was fine.

This is the second compounding bug alongside the deprecated
connectivity URI (covered by tests/captive-portal-uri-regressions.py).
Both fixes are needed for Helium to stop nagging.

Fix (modules/network/network.nix):
  * Only react to `connectivity-change` (drop the `up` branch).
  * Only react to `PORTAL` (drop `LIMITED` — there's nothing to log
    into when the network is reachable but the probe failed).
  * Skip non-WiFi interfaces — captive portals are a WiFi-only
    phenomenon; ethernet never has portals to log in to.
  * Still launch Helium with the 1.1.1.1 redirect-bait URL.
  * Still launch via systemd-run (not su) for the no-TTY case.

The URI is asserted in tests/captive-portal-uri-regressions.py.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NETWORK = ROOT / "modules" / "network" / "network.nix"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(NETWORK.exists(), f"{NETWORK} is missing")
src = NETWORK.read_text(encoding="utf-8")

# Find the dispatcher attribute open. The text value is the
# indented string `'' ... ''` on the lines following. We
# capture the dispatcher by tracking Nix brace depth from the
# attribute open to the matching close.
DISPATCHER_OPEN = '30-captive-portal.sh" = {'
i_open = src.find(DISPATCHER_OPEN)
require(i_open > 0, f"could not find dispatcher attribute open marker")
# Move to the `{` and walk forward tracking depth.
i_brace = src.find("{", i_open)
require(i_brace > 0, "could not find opening brace after dispatcher")
depth = 0
i = i_brace
while i < len(src):
    ch = src[i]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            break
    i += 1
require(depth == 0, "unbalanced braces while scanning dispatcher")
# `i` is now the position of the closing `}`. The body of the
# dispatcher is between i_brace and i.
body = src[i_brace + 1 : i]

# Strip comments to avoid false matches in the parent module's
# documentation that describes what we DO NOT do.
body_stripped = "\n".join(
    line for line in body.splitlines()
    if not line.lstrip().startswith("#")
)

# 1. `up` branch must be gone.
require(
    '"$2" != "connectivity-change"' in body_stripped,
    "dispatcher must reject all actions except connectivity-change "
    "(the `up` branch duplicated Helium launches on every DHCP renew — "
    "see commit message)"
)
require(
    "up)" not in body_stripped,
    "dispatcher must NOT have an `up` case in its action switch "
    "(removed; was firing on every DHCP renew of enp10s0/wlp7s0)"
)

# 2. Only PORTAL — not LIMITED.
require(
    "PORTAL" in body_stripped,
    "dispatcher must check for PORTAL state"
)
require(
    "LIMITED" not in body_stripped,
    "dispatcher must NOT check for LIMITED state (LIMITED means the "
    "connectivity probe failed but the network is reachable — opening "
    "Helium is just annoying; only PORTAL means there's a login)"
)

# 3. WiFi-only — skip ethernet.
require(
    "wlan*" in body_stripped or "wlp*" in body_stripped or "wifi*" in body_stripped,
    "dispatcher must gate on WiFi interface names (wlan*/wlp*/wifi*)"
)
require(
    '*) exit 0' in body_stripped,
    "dispatcher must have a fallthrough `*) exit 0` for non-WiFi interfaces"
)

# 4. Still launches Helium with the redirect-bait URL.
require(
    "helium http://1.1.1.1" in body_stripped,
    "dispatcher must launch helium with the 1.1.1.1 redirect-bait URL"
)

# 5. Still uses systemd-run (not su).
require(
    "systemd-run" in body_stripped,
    "dispatcher must use systemd-run (not su) — su requires a TTY"
)

print(
    "modules/network/network.nix (captive portal dispatcher gates on "
    "WiFi + connectivity-change + PORTAL only — no LAN spam): PASS"
)
sys.exit(0)