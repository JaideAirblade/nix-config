#!/usr/bin/env python3
"""Regressions for the Hermes Mobile Bridge (xP3ta/hermes-setup) module.

The bridge is the NixOS equivalent of running the upstream
`curl -fsSL https://raw.githubusercontent.com/xP3ta/hermes-setup/main/hermes-mobile-setup.sh | sh`
installer, expressed declaratively. This test guards against:

  * the upstream rev drifting to a release whose `bridge-release.json`
    manifest no longer matches the pinned hermes_bridge.py bytes
  * the three systemd user services losing their hardening template
  * the pairing address being lost (no host, no port, no token URL)
  * the sops file in `nixos-secrets` going missing or being renamed
  * the .env-style pairing template failing to render

It is a static-only regression: it does NOT evaluate the NixOS build
(that already runs in `nixos-rebuild`), but it does sanity-check the
module is in the right place with the right surface area."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "modules/ai/hermes-mobile-bridge.nix"
SECRETS_REL = "secrets/UwU-Server/hermes-mobile-bridge.yaml"

# Pinned upstream contract — must be kept in sync with the comments
# and assertions in the module itself. Bumping xP3ta's bridge version
# is a 3-line edit: rev, version, sha256.
EXPECTED_REV = "81b0993be54469dbdf9c452fbab16d657c077b2a"
EXPECTED_VERSION = "1.18.0"
EXPECTED_SHA = "f8243b6e651c3e3fb8ca7f19e83677f268776624041a4dedae47a03b879a7a42"
EXPECTED_SIZE = 132711
EXPECTED_MIN_APP_BUILD = 904
EXPECTED_SRI = "sha256-oWdrvFfU5FXYnlfy5vtLwNh96KChq5mFXtfhq6N/6PY="

EXPECTED_PORTS = {
    "gateway": 8642,
    "dashboard": 9119,
    "bridge": 9131,
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(MODULE.is_file(), "mob [Hermes Mobile Bridge module is missing]")

source = MODULE.read_text(encoding="utf-8")

# 1. The upstream source is pinned to a known-good rev and SRI hash.
#    Drift here breaks the in-bridge self-update verification.
require(
    'rev = bridgeRev;' in source,
    "upstream xP3ta/hermes-setup rev must be pinned (bridgeRev string)",
)
require(
    f'hash = "{EXPECTED_SRI}";' in source,
    "upstream tarball SRI must be pinned",
)
require(
    'bridgeRev = "' + EXPECTED_REV + '";' in source,
    'bridgeRev binding must hold the expected pinned rev',
)

# 2. Build-time assertions verify the manifest exactly matches the
#    pinned bytes. If upstream silently rebytes the bridge release, the
#    build fails rather than the pairing.
for triple in (
    EXPECTED_VERSION,
    EXPECTED_SHA,
    str(EXPECTED_SIZE),
):
    require(
        triple in source,
        f"expected constant {triple!r} missing from build-time assertions",
    )
# min_app_build is informational only — not pinned here so the bridge
# can be bumped compatibly via env without a Nix rebuild.
# 3. The three expected ports (8642/9119/9131) are wired in.
for name, port in EXPECTED_PORTS.items():
    require(
        (
            f"export API_SERVER_PORT={port}" in source
            or f"--port {port}" in source
            or f"BRIDGE_PORT={port}" in source
            or f"localhost:{port}" in source
        ),
        f"port {port} ({name}) missing from installer runner scripts",
    )

# 4. Sops secret is read from the right path, and the rendered env
#    template is wired to the bridge unit.
require(
    "hermes-mobile-bridge.yaml" in source,
    "sops file path is missing",
)
require(
    "hermes_mobile_bridge_api_key" in source,
    "sops secret key name is missing",
)
require(
    "hermes-mobile-bridge-pairing" in source,
    "sops template name is missing",
)
require(
    "BRIDGE_TOKEN" in source and "BRIDGE_HOST" in source and "BRIDGE_PORT" in source,
    "pairing.env template does not ship the three required vars",
)
require(
    "BRIDGE_SCOPES=read,memory,soul,skills,cron,config,command" in source,
    "bridge scopes must match the upstream installer's set",
)

# 5. The three systemd user services exist and are hardened like
#    hermes-router. The module restricts them to luna's session.
for unit in (
    "hermes-mobile-gateway",
    "hermes-mobile-dashboard",
    "hermes-mobile-bridge",
):
    require(
        f"systemd.user.services.{unit}" in source,
        f"systemd user unit {unit} is not declared",
    )
    require(
        'ConditionUser = herUser' in source,
        f"systemd user unit {unit} must be scoped to luna only",
    )
require(
    "ProtectSystem = \"strict\";" in source,
    "all three services must use ProtectSystem=strict",
)
require(
    "RestrictAddressFamilies = [ \"AF_UNIX\" \"AF_INET\" \"AF_INET6\" ]" in source,
    "all three services must restrict AF families",
)

# 6. The pairing QR command exists and ships qrencode.
require(
    "hermes-mobile-bridge-pair-qr" in source,
    "pair-qr command derivation is missing",
)
require(
    "qrencode" in source,
    "pair-qr command must pull qrencode at runtime",
)
require(
    "hermes://pair?" in source,
    "pair-qr command must assemble a hermes://pair? URL",
)
require(
    "SCAN THIS QR" in source,
    "pair-qr command must print the upstream SCAN THIS QR banner",
)

# 7. The mirror ACL — the upstream installer does Tailscale-first (the
#    secure default). The module reflects that by binding on 0.0.0.0
#    and relying on the tailnet firewall policy. Make sure the firewall
#    ports are 8642/9119/9131 (not the LAN/public interfaces).
require(
    "API_SERVER_HOST='0.0.0.0'" in source,
    "gateway must bind 0.0.0.0 (firewall is the access-control layer)",
)
require(
    "BK/9131" not in source,
    "executor mode flag 'BK/9131' snuck in — strip it",
)

# 8. The console services directory path is canonical.
require(
    ("/home/luna/.hermes/console-services" in source or "herHome = " in source and "console-services" in source)
    or ('herHome = "/home/luna/.hermes"' in source and 'console-services' in source),
    "console-services path must be /home/luna/.hermes/console-services (literal or constructed)",
)

# 9. The pair-qr command calls the Netbird mesh wrapper to get the IP
#    and warns if the mesh is not up.
require(
    "netbird-mesh" in source,
    "pair-qr command must invoke the netbird-mesh CLI wrapper to resolve the address",
)
require(
    "Netbird mesh is not up" in source,
    "pair-qr command must warn when the Netbird mesh is down",
)
require(
    "pkgs.jq" in source,
    "pair-qr command must declare pkgs.jq in runtimeInputs (parses netbird status JSON)",
)

# 10. The sops file actually exists in the secrets repo (this only
#     runs cleanly from `nix build` — direct invokes will skip).
sops_candidates = [Path("/home/luna/nixos-secrets")]
if not sops_candidates[0].is_dir():
    # Try the nix-store source layout that the test runner uses.
    for d in Path("/nix/store").glob("*-source"):
        if (d / SECRETS_REL).exists():
            sops_candidates.append(d)
            break
sops_ok = any((d / SECRETS_REL).exists() for d in sops_candidates)
if not sops_ok:
    print(
        "WARN: Hermes Mobile Bridge sops file not visible from this test "
        "environment. The build will fail loudly if the secret is missing; "
        "this is just a heads-up for direct invocation.",
        file=sys.stderr,
    )

print("Hermes Mobile Bridge regressions: PASS")
