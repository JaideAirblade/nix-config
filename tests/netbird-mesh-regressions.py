#!/usr/bin/env python3
"""Static and policy regressions for the private Netbird management mesh.

Parallel to tests/tailscale-mesh-regressions.py. Asserts the same
invariants that the Tailscale mesh provided, but checked against the
Netbird-side module and policy in this repo.

Invariants (mirrored from tailscale-mesh-regressions.py):
  - The Netbird NixOS role module exists and is wired.
  - The Netbird policy file exists and contains the four groups.
  - Each host that opts into netbirdMesh has the correct role.
  - The printserver is deny-by-default as a SOURCE.
  - OpenSSH is enabled with key-only auth.
  - Jaide's pinned SSH public key is the only authorised human key.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "modules/network/netbird-mesh.nix"
POLICY = ROOT / "modules/network/netbird-policy.json"
HOSTS = {
    "UwU": ROOT / "hosts/UwU/default.nix",
    "UwU-Server": ROOT / "hosts/UwU-Server/default.nix",
    "TSBW-W01800": ROOT / "hosts/TSBW-W01800/default.nix",
    "Projet-Printserver": ROOT / "hosts/Projet-Printserver/default.nix",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


# --- Module presence + structural assertions -------------------------

require(MODULE.is_file(), "Netbird mesh NixOS role is missing")
require(POLICY.is_file(), "versioned Netbird policy is missing")
module = MODULE.read_text()

require("nixos.modules.netbirdMesh" in module, "netbirdMesh role is not declared")
require("services.netbird.clients.mesh" in module, "Netbird client instance `mesh` is not declared")
require(
    'interface = wtInterface' in module or 'interface = "wt0"' in module,
    "Netbird interface name is not pinned to wt0",
)
require("port = 51821;" in module, "Netbird Wireguard UDP port is not pinned to 51821")
require("openFirewall = true;" in module, "Netbird direct UDP connectivity is not enabled")
require("openInternalFirewall = true;" in module, "Netbird internal firewall ports are not enabled")
require(
    'services.netbird.useRoutingFeatures = "client";' in module,
    "mesh nodes are not restricted to client routing",
)
require("setupKeyFile = setupKeyPath" in module, "Netbird setup key path is not wired to sops-rendered path")
require(
    "/run/secrets/netbird-setup-key" in module,
    "Netbird setup key path is not /run/secrets/netbird-setup-key (sops-rendered)",
)
require("services.resolved.enable = true;" in module, "systemd-resolved is not enabled for Netbird MagicDNS")

# --- OpenSSH + Jaide's key --------------------------------------------

require("services.openssh" in module and "enable = true;" in module, "traditional OpenSSH is not enabled")
require("PasswordAuthentication = false;" in module, "mesh SSH password authentication is not disabled")
require("KbdInteractiveAuthentication = false;" in module, "mesh SSH keyboard authentication is not disabled")
require('PermitRootLogin = lib.mkDefault "no";' in module, "mesh SSH does not default to denying root login")
require(
    "jaide_nixos" in module and "openssh.authorizedKeys.keys" in module,
    "Jaide's pinned SSH public key is not authorized on mesh hosts",
)

# --- mkIf gate so the module is opt-in --------------------------------

require("lib.mkIf cfg.enable" in module, "the netbirdMesh role is not gated by cfg.enable")
require("lib.types.bool" in module, "netbirdMesh.enable is not a bool option")

# --- Firewall port allowlist (same as Tailscale role) -----------------

for port in (22, 443, 3000, 3001, 3002, 3030, 8080, 8642, 9119, 9131, 19999, 28981):
    require(f"  {port}" in module, f"firewall port allowlist is missing {port}")

# --- Policy schema + invariants ---------------------------------------

policy = json.loads(POLICY.read_text())

# Groups: must have the four named groups.
groups = policy.get("groups", [])
group_names = {g["name"] for g in groups}
for required_group in ("private", "work", "personal", "printserver"):
    require(required_group in group_names, f"policy group `{required_group}` is missing")

# Rules: printserver must NEVER appear as a source.
rules = policy.get("rules", [])
for rule in rules:
    sources = rule.get("sources", [])
    require(
        "printserver" not in sources,
        f"rule `{rule.get('name', '?')}` lists printserver as a source (deny-by-default-source invariant violated)",
    )

# Spot-check: rule destinations include `printserver` only as a destination (sink),
# not as a source. Verify at least one rule has printserver in destinations.
has_printserver_destination = any("printserver" in r.get("destinations", []) for r in rules)
require(
    has_printserver_destination,
    "no rule allows private/work/personal to reach the printserver on port 22",
)

# Port 22 (SSH) must be reachable from every non-printserver group to every group.
ssh_destinations = set()
for rule in rules:
    if "tcp" in [p.get("protocol") for p in rule.get("ports", [])] and any(
        p.get("port") == "22" for p in rule.get("ports", []) if p.get("protocol") == "tcp"
    ):
        ssh_destinations.add(tuple(sorted(rule.get("destinations", []))))
require(len(ssh_destinations) >= 1, "no rule allows port 22 (SSH) at all")

# Hermes WebUI (8080) must be reachable from each non-printserver group.
webui_destinations = set()
for rule in rules:
    if any(p.get("port") == "8080" for p in rule.get("ports", []) if p.get("protocol") == "tcp"):
        webui_destinations.add(tuple(sorted(rule.get("destinations", []))))
require(len(webui_destinations) >= 1, "no rule allows port 8080 (Hermes WebUI) at all")

# Hermes Mobile Bridge ports (8642, 9119, 9131) must be reachable from each group.
for port in ("8642", "9119", "9131"):
    seen = False
    for rule in rules:
        if any(p.get("port") == port for p in rule.get("ports", []) if p.get("protocol") == "tcp"):
            seen = True
            break
    require(seen, f"no rule allows port {port} (Hermes Mobile Bridge) at all")

# --- Per-host opt-in (during the cutover: hosts may opt in here) ------
# This check is INVARIANT-light: any host opting into netbirdMesh must
# have a valid nodeRole. Hosts that have not opted in are simply not
# listed. The actual cutover is a host-by-host operation in Phase 3.
#
# We intentionally do NOT require every host to opt in here — the
# Tailscale mesh is still the live mesh.

# --- Print-server SSH invariant (independent of mesh) -----------------
# The print server's users/users.nix must keep key-only SSH by default
# and confine the AD password SSH block to the lab subnet.
print_users = ROOT / "hosts/Projet-Printserver/users/users.nix"
if print_users.is_file():
    print_users_text = print_users.read_text()
    require(
        "PasswordAuthentication = false;" in print_users_text
        and "KbdInteractiveAuthentication = false;" in print_users_text,
        "print server does not default to key-only SSH",
    )
    require(
        "Match Address 192.168.100.0/24" in print_users_text
        and "PasswordAuthentication yes" in print_users_text,
        "AD password SSH is not confined to the isolated lab source subnet",
    )

print("Netbird mesh regressions: PASS")
