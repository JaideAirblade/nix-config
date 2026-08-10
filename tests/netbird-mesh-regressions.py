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
    "sops.secrets.netbird-setup-key" in module,
    "the netbird-mesh module does not declare the sops secret for the setup key with the correct YAML key name (netbird-setup-key)",
)
require(
    "inputs.nixos-secrets" in module,
    "the netbird-mesh module does not reference the nixos-secrets flake input",
)
require(
    "/run/secrets/netbird-setup-key" in module,
    "Netbird setup key path is not /run/secrets/netbird-setup-key (sops-rendered)",
)
# systemd-resolved is intentionally NOT enabled by the Netbird mesh module
# because UwU's existing direct-link config pins environment.etc."resolv.conf"
# to AdGuard Home, which conflicts with resolved's stub-resolv.conf
# assignment. Openresolv is used as the default DNS manager when resolved
# is disabled. The split-horizon DNS forward for Netbird's managed domain
# is wired in Phase 3 (deferred).
require(
    "services.resolved.enable = true;" not in module,
    "Netbird mesh should NOT enable systemd-resolved (conflicts with AdGuard resolv.conf pin)",
)

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

# --- DMS user-facing `netbird` shim on UwU --------------------------------
# The DMS "NetbirdStatus" plugin (github.com/Dadangdut33/dms-plugins/NetbirdStatus)
# probes for a `netbird` binary on $PATH by running `which netbird`. The
# NixOS netbird module exposes the per-instance wrapper as `netbird-mesh`
# (the `bin.suffix` is the instance name), so the plugin's probe fails
# even when the mesh is up. The remediation is a host-scoped shim that
# wraps the upstream wrapper under the name `netbird`. The shim file
# lives at hosts/UwU/shell/dms-netbird-shim.nix and is auto-imported
# by collectModules; it must (a) exist on disk, (b) be wired into the
# UwU host's flake-parts namespace, and (c) default to enabled once
# the netbirdMesh role is enabled. If any of these regresses, the
# DMS plugin will print "NetBird not installed" again.
uwu_shim = ROOT / "hosts/UwU/shell/dms-netbird-shim.nix"
require(uwu_shim.is_file(), "UwU DMS netbird shim file is missing")

uwu_shim_text = uwu_shim.read_text()
require(
    "nixos.hosts.\"UwU\"" in uwu_shim_text,
    "UwU DMS netbird shim is not host-scoped to UwU (must live under nixos.hosts.\"UwU\")",
)
require(
    "config.services.netbird.clients.mesh.wrapper" in uwu_shim_text,
    "UwU DMS netbird shim does not wrap services.netbird.clients.mesh.wrapper",
)
require(
    "environment.systemPackages" in uwu_shim_text,
    "UwU DMS netbird shim does not add the shim package to environment.systemPackages",
)
require(
    'lib.mkIf (cfg.enable && cfg.dms.enable)' in uwu_shim_text,
    "UwU DMS netbird shim is not gated by services.netbirdMesh.dms.enable",
)
require(
    "services.netbirdMesh.dms" in uwu_shim_text and "dms.enable" in uwu_shim_text,
    "UwU DMS netbird shim does not declare the services.netbirdMesh.dms.enable option",
)

# The netbird-mesh role module must expose a daemon-socket-access option
# so hosts with `mkForce` on `users.users.jaide.extraGroups` (e.g. the
# work laptop) can opt back in to the `netbird-mesh` group. The canonical
# `jaide` user is added unconditionally inside the role module's
# `users.users.jaide.extraGroups = lib.mkAfter [ "netbird-mesh" ]` block,
# so asserting the option's existence is enough to know the wiring logic
# is reachable for additional users.
require(
    "daemonSocketUsers" in module,
    "netbird-mesh role module does not declare the daemonSocketUsers option",
)
require(
    "lib.types.listOf lib.types.str" in module,
    "netbird-mesh role module's daemonSocketUsers is not a listOf str",
)
require(
    '"netbird-mesh"' in module and "extraGroups" in module,
    "netbird-mesh role module does not wire the `netbird-mesh` group into users' extraGroups",
)

# The shim must be reachable by the flake's collectModules walker. The
# walker excludes `default.nix` and any path listed in flake.nix's
# `dendriticExceptions` map. The shim file is neither, so it is picked
# up automatically. If a future contributor lists it as an exception
# by mistake, the walker will skip it and the shim will silently
# disappear from the system profile — exactly the bug we are
# regression-testing. Read flake.nix and assert the shim is not in
# the exception set.
flake_text = (ROOT / "flake.nix").read_text()
import re
exc_block = re.search(r"dendriticExceptions\s*=\s*\{([^}]*)\}", flake_text, re.DOTALL)
if exc_block is None:
    raise SystemExit("FAIL: flake.nix does not declare a `dendriticExceptions` map")
exc_paths = re.findall(r'"([^"]+)"', exc_block.group(1))
require(
    "hosts/UwU/shell/dms-netbird-shim.nix" not in exc_paths,
    "UwU DMS netbird shim is listed in flake.nix's dendriticExceptions — "
    "the walker will skip it and the shim will silently disappear",
)

# --- Mesh DNS resolver (per-host) -------------------------------------
# UwU-Server opts in to bind the daemon on a stable loopback address
# so AdGuard can forward `*.netbird.cloud` via a known socket. UwU
# and TSBW leave it at the default (daemon's own mesh IP at port 5053).
require(
    "dnsResolverAddress" in module,
    "netbird-mesh role module does not declare the dnsResolverAddress option",
)
require(
    "dnsResolverPort" in module,
    "netbird-mesh role module does not declare the dnsResolverPort option",
)
uwu_server_text = HOSTS["UwU-Server"].read_text()
require(
    'dnsResolverAddress = "127.0.0.1"' in uwu_server_text,
    "UwU-Server does not pin dnsResolverAddress to 127.0.0.1 (loopback to AdGuard)",
)
require(
    "dnsResolverPort = 5353" in uwu_server_text,
    "UwU-Server does not pin dnsResolverPort to 5353 (avoids port-53 AdGuard conflict and CAP_NET_BIND_SERVICE)",
)
# The role module wires `dns-resolver = lib.mkIf (cfg.dnsResolverAddress != null)`
# into services.netbird.clients.mesh, so the upstream NixOS module's
# dns-resolver.address / dns-resolver.port options get populated.
require(
    "dns-resolver" in module and "cfg.dnsResolverAddress" in module,
    "netbird-mesh role module does not wire dnsResolverAddress into services.netbird.clients.mesh.dns-resolver",
)

# --- AdGuard split-horizon DNS forward (UwU-Server) --------------------
# Without this forward, queries for `*.netbird.cloud` go to Unbound
# (public recursive), which resolves them via the public netbird DNS —
# works for `uwu-server.netbird.cloud` etc., but the answer is the
# daemon's *current* mesh IP, which can lag a fresh enrollment. The
# local netbird daemon always has the freshest map from the management
# plane, so the forward chain is the right path.
adguard_cfg = (ROOT / "hosts/UwU-Server/network/direct-link.nix").read_text()
require(
    "[/netbird.cloud/]127.0.0.1:5353" in adguard_cfg,
    "AdGuard on UwU-Server is not configured to forward `*.netbird.cloud` to "
    "the loopback netbird daemon (127.0.0.1:5353). DNS for mesh hostnames will "
    "leak to Unbound / public DNS.",
)
# The non-mesh upstream (Unbound on 127.0.0.1:5335) must still be present.
require(
    "127.0.0.1:5335" in adguard_cfg,
    "AdGuard on UwU-Server is missing the Unbound upstream (127.0.0.1:5335). "
    "Public DNS resolution will break for non-mesh queries.",
)

# --- TSBW dnsproxy: forward mesh DNS to UwU-Server --------------------
# TSBW uses dnsproxy (not AdGuard) and has its own upstream chain.
# Without the per-domain forward, `ssh uwu-server` from TSBW silently
# fails to resolve. The IP is hardcoded because the netbird mesh IP
# of UwU-Server is itself a literal, not a DNS answer.
tsbw_dns_cfg = (ROOT / "hosts/TSBW-W01800/network/dns.nix").read_text()
require(
    "[/netbird.cloud/]100.77.228.137:53" in tsbw_dns_cfg,
    "TSBW dnsproxy is not configured to forward `*.netbird.cloud` to "
    "UwU-Server's AdGuard over the mesh (100.77.228.137:53). Mesh hostname "
    "resolution from TSBW will silently break.",
)

# --- SSH fleet aliases -----------------------------------------------
# Every host that opts into automationAccounts gets Luna's declarative
# ssh_config with `Host` blocks for uwu / uwu-server / tsbw /
# uwu-phone. Without the aliases, every cross-host SSH needs
# `ssh -i ~/.ssh/id_ed25519 luna@100.77.x.x` — the exact ergonomic
# pain documented in the 2026-08-09 Netbird migration session log.
private_accounts = (ROOT / "modules/users/private-accounts.nix").read_text()
require(
    "environment.etc.\"luna/ssh_config\".text" in private_accounts,
    "modules/users/private-accounts.nix is not declaring luna's ssh_config (move from per-host)",
)
for alias in ("uwu-server", "uwu", "tsbw", "uwu-phone"):
    require(
        f"Host {alias}" in private_accounts,
        f"ssh_config is missing Host block for `{alias}`",
    )
# Each alias must carry a HostName (literal mesh IP) so it works even
# when the magic-DNS resolver is unreachable (the eBPF proxy
# situation the TSBW-W01800 host saw in 2026-08-08).
import re as _re
alias_blocks = _re.findall(
    r"^Host\s+(\S+(?:\s+\S+)*)\s*\n((?:\s+\S+\s*\n)+)",
    private_accounts,
    _re.MULTILINE,
)
for hosts_line, block in alias_blocks:
    if "github.com" in hosts_line:
        continue  # GitHub Host block is exempt from the HostName requirement
    require(
        "HostName" in block,
        f"ssh_config Host block `{hosts_line.split()[0]}` is missing HostName "
        f"(would silently fail when magic-DNS is unreachable)",
    )

# The per-host users/users.nix must wire ~/.ssh/config → /etc/luna/ssh_config
# (rendered by automationAccounts). UwU-Server already had this; UwU was
# missing it. TSBW doesn't have luna at all, so the symlink isn't needed there.
for host in ("UwU-Server", "UwU"):
    users_text = (ROOT / f"hosts/{host}/users/users.nix").read_text()
    require(
        "L+ /home/luna/.ssh/config" in users_text and "/etc/luna/ssh_config" in users_text,
        f"hosts/{host}/users/users.nix is not wiring ~/.ssh/config → /etc/luna/ssh_config",
    )

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
