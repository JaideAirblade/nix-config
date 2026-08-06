#!/usr/bin/env python3
"""Static and policy regressions for the private Tailscale management mesh."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "modules/network/tailscale-mesh.nix"
POLICY = ROOT / "modules/network/tailscale-policy.json"
PRINT_USERS = ROOT / "hosts/Projet-Printserver/users/users.nix"
HOSTS = {
    "UwU": ROOT / "hosts/UwU/default.nix",
    "UwU-Server": ROOT / "hosts/UwU-Server/default.nix",
    "TSBW-W01800": ROOT / "hosts/TSBW-W01800/default.nix",
    "Projet-Printserver": ROOT / "hosts/Projet-Printserver/default.nix",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(MODULE.is_file(), "Tailscale mesh NixOS role is missing")
require(POLICY.is_file(), "versioned tailnet policy is missing")
module = MODULE.read_text()
print_users = PRINT_USERS.read_text()

require("nixos.modules.remoteMesh" in module, "remoteMesh role is not declared")
require("services.tailscale" in module and "enable = true;" in module, "Tailscale is not enabled")
require("openFirewall = true;" in module, "Tailscale direct UDP connectivity is not enabled")
require('useRoutingFeatures = "client";' in module, "mesh nodes are not restricted to client routing")
require("services.openssh" in module and "enable = true;" in module, "traditional OpenSSH is not enabled")
require("openFirewall = cfg.exposeSshOnLan;" in module, "LAN SSH exposure is not role-controlled")
require(
    re.search(
        r'networking\.firewall\.interfaces\.tailscale0\.allowedTCPPorts\s*=\s*\[\s*22\s*8080\s*\]\s*;',
        module,
    )
    is not None,
    "tailscale0 mesh firewall must allow only TCP/22 (SSH) and TCP/8080 (Hermes WebUI)",
)
require("PasswordAuthentication = false;" in module, "mesh SSH password authentication is not disabled")
require("KbdInteractiveAuthentication = false;" in module, "mesh SSH keyboard authentication is not disabled")
require(
    'cfg.nodeRole != "printserver"' not in module,
    "print-server mesh SSH bypasses key-only authentication",
)
require('PermitRootLogin = lib.mkDefault "no";' in module, "mesh SSH does not default to denying root login")
require("services.tailscale.authKeyFile" not in module, "an auth-key path was added before a SOPS secret exists")
require("--ssh" not in module, "Tailscale SSH replaced the pinned OpenSSH key trust path")
require(
    "jaide_nixos" in module and "openssh.authorizedKeys.keys" in module,
    "Jaide's pinned SSH public key is not authorized on mesh hosts",
)

expected = {
    "UwU": ("private", False),
    "UwU-Server": ("private", True),
    "TSBW-W01800": ("work", False),
    "Projet-Printserver": ("printserver", True),
}
for hostname, (role, expose_lan) in expected.items():
    text = HOSTS[hostname].read_text()
    require("config.nixos.modules.remoteMesh" in text, f"{hostname} does not select remoteMesh")
    require(f'nodeRole = "{role}";' in text, f"{hostname} has the wrong mesh role")
    value = "true" if expose_lan else "false"
    require(
        f"exposeSshOnLan = {value};" in text,
        f"{hostname} has the wrong LAN SSH exposure policy",
    )

policy = json.loads(POLICY.read_text())
tag_owners = policy.get("tagOwners", {})
for tag in ("tag:private", "tag:work", "tag:personal", "tag:printserver"):
    require(tag_owners.get(tag) == ["autogroup:admin"], f"{tag} lacks an admin-only owner")

require(
    "autogroup:member" not in POLICY.read_text(),
    "tailnet membership is broader than the explicitly tagged device inventory",
)

acls = policy.get("acls", [])
mesh_rule = next(
    (
        rule
        for rule in acls
        if set(rule.get("src", [])) == {"tag:private", "tag:work", "tag:personal"}
    ),
    None,
)
require(mesh_rule is not None, "private/work mesh source rule is missing")
assert mesh_rule is not None
mesh_destinations = set(mesh_rule.get("dst", []))
require(
    {"tag:private:22", "tag:work:22", "tag:personal:22", "tag:printserver:22"}.issubset(
        mesh_destinations
    ),
    "private/work/personal nodes cannot SSH to every approved destination",
)
require(
    "tag:private:8080" in mesh_destinations,
    "tag:private peers must be allowed to reach Hermes WebUI on TCP/8080",
)
require(
    {"tag:work:8080", "tag:personal:8080"}.issubset(mesh_destinations),
    "work and personal peers must also reach Hermes WebUI on TCP/8080 (phone + work laptop)",
)
require(
    all("tag:printserver" not in rule.get("src", []) for rule in acls),
    "print server is allowed to initiate tailnet traffic",
)

policy_tests = policy.get("tests", [])
print_test = next((test for test in policy_tests if test.get("src") == "tag:printserver"), None)
require(print_test is not None, "print-server source-denial policy test is missing")
assert print_test is not None
require(
    {"tag:private:22", "tag:work:22", "tag:personal:22"}.issubset(
        set(print_test.get("deny", []))
    ),
    "print-server source denial does not cover private, work, and personal nodes",
)

require(
    "PasswordAuthentication = false;" in print_users
    and "KbdInteractiveAuthentication = false;" in print_users,
    "print server does not default to key-only SSH",
)
require(
    "Match Address 192.168.100.0/24" in print_users
    and "PasswordAuthentication yes" in print_users
    and "KbdInteractiveAuthentication yes" in print_users,
    "AD password SSH is not confined to the isolated lab source subnet",
)

print("Tailscale mesh regressions: PASS")
