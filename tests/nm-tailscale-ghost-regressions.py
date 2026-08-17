#!/usr/bin/env python3
"""Regression test for the ghost tailscale0 NetworkManager adoption bug.

Symptom (2026-08-17): After the 2026-08-09 Netbird migration removed
Tailscale from the config, a stale `tailscale0` tun interface persists
in the kernel because tailscaled created it last time it ran. The
binary is gone, no systemd unit exists, but the device remains.

Without explicit exclusion, NetworkManager's nm-dispatcher treats
the virtual interface as a fresh connection, runs DHCP on it, and
floods the journal with lines like:

    Aug 17 19:07:04 UwU nm-dispatcher[64416]: Set DHCP hostname to \
        MacBookPro63 for tailscale0

…and `nmcli device status` lists:

    tailscale0  tun  connected  tailscale0

This test asserts the NixOS config keeps NetworkManager from managing
tun-style interfaces that aren't ours — specifically `tailscale*`
(the post-migration ghost) and `tun*` (NymVPN's tun0/tun1).

What we check:

  1. `hosts/UwU/packages/packages.nix` declares
     `networking.networkmanager.unmanaged` with both `tun*` and
     `tailscale*` interface-name patterns.
  2. The comment in that file mentions the 2026-08-09 Netbird
     migration and the ghost-interface failure mode (so future
     contributors understand why both patterns are there).
  3. `modules/network/netbird-mesh.nix` does NOT mention `tailscale0`
     (it's dead and we don't want anyone re-introducing the interface).
  4. The test fires even though Tailscale is uninstalled — protects
     against a future "add tailscale for compat" PR that forgets to
     also re-exclude the ghost interface from NM.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UWU_PACKAGES = ROOT / "hosts" / "UwU" / "packages" / "packages.nix"
NETBIRD_MESH = ROOT / "modules" / "network" / "netbird-mesh.nix"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(UWU_PACKAGES.exists(), "hosts/UwU/packages/packages.nix is missing")
require(NETBIRD_MESH.exists(), "modules/network/netbird-mesh.nix is missing")

packages = UWU_PACKAGES.read_text(encoding="utf-8")
netbird = NETBIRD_MESH.read_text(encoding="utf-8")

# 1. The unmanaged list includes both tun* and tailscale*.
require("networking.networkmanager.unmanaged" in packages,
        "hosts/UwU/packages/packages.nix must declare networking.networkmanager.unmanaged")
require('"interface-name:tun*"' in packages,
        "unmanaged list must include 'interface-name:tun*' (NymVPN exclusion)")
require('"interface-name:tailscale*"' in packages,
        "unmanaged list must include 'interface-name:tailscale*' "
        "(post-migration ghost — tailscaled uninstalled 2026-08-09 but the "
        "tun-style device persists in the kernel until reboot or manual delete)")

# 2. The migration context is documented in the comment so future
# contributors don't remove the tailscale* pattern thinking it's dead.
# Look for the 2026-08-09 Netbird migration reference near the
# unmanaged declaration.
# Walk a window around the unmanaged declaration for the migration note.
unmanaged_idx = packages.find("interface-name:tailscale*")
require(unmanaged_idx > 0,
        "tailscale* pattern must exist (see assertion above)")
window = packages[max(0, unmanaged_idx - 1200):unmanaged_idx + 200]
require("Netbird" in window or "netbird" in window,
        "comment near tailscale* pattern must reference the Netbird migration")
require("2026-08-09" in window,
        "comment near tailscale* pattern must reference the 2026-08-09 migration date")
require("nm-dispatcher" in window or "NetworkManager" in window,
        "comment must explain that NM adopts ghost tailscale0 without exclusion")

# 3. netbird-mesh.nix must not mention the dead tailscale0 (avoid
# regression — if a future PR reintroduces tailscale, this test fails
# and forces a deliberate decision).
require("tailscale0" not in netbird,
        "modules/network/netbird-mesh.nix must NOT reference tailscale0 "
        "(Tailscale is uninstalled as of the 2026-08-09 Netbird migration)")

print("hosts/UwU/packages/packages.nix (NM exclusion of tun* + tailscale* — protects against ghost interface): PASS")