#!/usr/bin/env python3
"""Regression: NetworkManager connectivity check URL must resolve.

Symptom (2026-08-17): the NixOS config sets
`networking.networkmanager.settings.connectivity.uri` to
`http://connectivity-check.networkmanager.dev/` — the "newer"
GNOME URL. That domain no longer resolves (deprecated upstream).
NetworkManager's HTTP check fails every 5 minutes (the configured
interval), leaving state at `limited` permanently, which the
captive portal dispatcher treats as portal and fires Helium
with `http://1.1.1.1` — open VERY often.

Fix: switch to `http://nmcheck.gnome.org/check_network_status.txt`
(the default that actually works) and update the expected `response`
field to `"NetworkManager is online"` (the body nmcheck.gnome.org
returns).

This test asserts:
  1. modules/network/network.nix configures the connectivity check
     URI to a host that resolves (nmcheck.gnome.org).
  2. The configured `response` field matches the literal body the
     URL returns, so a future URL swap doesn't regress the response
     expectation.
  3. The deprecated URL is NOT present in the source (non-comment).
  4. The dispatcher script (30-captive-portal.sh) still exists.
  5. (Optional) Live HTTP check that the URL actually responds.

The dispatcher's state gating (PORTAL vs LIMITED, `up` vs
`connectivity-change`, WiFi vs ethernet) is asserted separately
in `tests/captive-portal-dispatcher-regressions.py`.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NETWORK = ROOT / "modules" / "network" / "network.nix"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(NETWORK.exists(), f"{NETWORK} is missing")
src = NETWORK.read_text(encoding="utf-8")

# 1. URI must be the working one.
require(
    'http://nmcheck.gnome.org/check_network_status.txt' in src,
    "modules/network/network.nix must use the working "
    "http://nmcheck.gnome.org/check_network_status.txt URI "
    "(http://connectivity-check.networkmanager.dev/ is deprecated "
    "and no longer resolves — causes 24/7 captive portal dispatcher firing)"
)

# 2. Response must match the literal body that URL returns.
require(
    'response = "NetworkManager is online";' in src,
    "modules/network/network.nix must set the connectivity response "
    "to \"NetworkManager is online\" (the literal body "
    "nmcheck.gnome.org returns)"
)

# 3. Deprecated URL must NOT be present (in non-comment lines).
# The module file may legitimately mention the deprecated URL in a
# comment to prevent reintroduction — strip comments before scanning.
src_stripped = "\n".join(
    line for line in src.splitlines()
    if not line.lstrip().startswith("#")
)
require(
    "connectivity-check.networkmanager.dev" not in src_stripped,
    "modules/network/network.nix must NOT reference "
    "connectivity-check.networkmanager.dev in non-comment lines "
    "(the comment block is allowed to keep the deprecation warning visible)"
)

# 4. The dispatcher script definition must still be present.
require(
    "30-captive-portal.sh" in src,
    "modules/network/network.nix must still define the "
    "30-captive-portal.sh dispatcher"
)

# 5. Network reachability — best-effort live check that the configured
# URL actually responds with the expected body. Strongest evidence
# the URI assumption is correct. Skipped if offline / no curl.
try:
    result = subprocess.run(
        [
            "curl",
            "-sS",
            "-m",
            "10",
            "http://nmcheck.gnome.org/check_network_status.txt",
        ],
        capture_output=True,
        text=True,
        timeout=15,
    )
    body = result.stdout.strip()
    require(
        body == "NetworkManager is online",
        f"nmcheck.gnome.org returned {body!r}, expected "
        f"'NetworkManager is online' — URI assumption invalid",
    )
    print(
        "modules/network/network.nix (NM connectivity URI works "
        "end-to-end, live check confirmed): PASS"
    )
except (FileNotFoundError, subprocess.TimeoutExpired) as e:
    # Offline / no curl — accept the static checks as sufficient.
    print(
        "modules/network/network.nix (NM connectivity URI correct; "
        f"live check skipped: {e.__class__.__name__}): PASS"
    )
    sys.exit(0)