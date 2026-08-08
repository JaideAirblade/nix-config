#!/usr/bin/env python3
"""Regression contract for the staged OmniRoute Docker deployment on
UwU-Server. Enforces: Hermes Router stays enabled, OmniRoute runs in
a pinned-content-digest container, binds only to 127.0.0.1:8320 during
the staged phase, sops key is reused from the existing
hermes_router_proxy_api_key, and the image is consumed from
`diegosouzapw/omniroute` with a content-addressed digest."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "pkgs/omniroute/default.nix"
MODULE = ROOT / "hosts/UwU-Server/ai/omniroute.nix"
FLAKE = ROOT / "flake.nix"
ROUTER = ROOT / "hosts/UwU-Server/ai/hermes-router.nix"
DEFAULTS = ROOT / "pkgs/default.nix"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(PACKAGE.exists(), "pkgs/omniroute/default.nix is missing")
require(MODULE.exists(), "hosts/UwU-Server/ai/omniroute.nix is missing")
require(ROUTER.exists(), "legacy hermes-router module is missing")
require(FLAKE.exists(), "flake.nix is missing")
require(DEFAULTS.exists(), "pkgs/default.nix is missing")

package = PACKAGE.read_text(encoding="utf-8")
module = MODULE.read_text(encoding="utf-8")
flake = FLAKE.read_text(encoding="utf-8")
router = ROUTER.read_text(encoding="utf-8")
defaults = DEFAULTS.read_text(encoding="utf-8")

# 1. Package must pin the OCI digest (no `latest` tag, no fake hash).
for needle in (
    'dockerTools.pullImage',
    'imageName = "diegosouzapw/omniroute";',
    'imageDigest = "sha256:92c768c56e2de32c51a0621ef182835018b00b288c9bb235c5c5e4514658c1a1";',
    'finalImageName = "diegosouzapw/omniroute";',
):
    require(needle in package, f"missing image pin: {needle}")
require('diegosouzapw/omniroute:latest' not in package,
        "package must not reference the 'diegosouzapw/omniroute:latest' tag")
require('tag = "latest"' not in package,
        "package must not use a 'latest' tag attribute")
require("lib.fakeSha256" not in package, "package must not still use lib.fakeSha256; first build fills it")
require("sha256-3XPJB5X12mJIXEzf36IskKcIyrAm3xHPrKA9KjSfUNI=" in package,
        "package must pin the fixed-output sha256 captured by the first nix build")

# 2. Package must be registered in pkgs/default.nix.
require("omniroute = pkgs.callPackage ./omniroute { };" in defaults,
        "pkgs/default.nix must register pkgs.omniroute")

# 3. Module must NOT take over port 8319, must NOT disable hermes-router,
# and must run on 127.0.0.1:8320 only.
for forbidden in (
    "mkForce false;",
    "systemd.services.hermes-router.enable =",
    "--publish 127.0.0.1:8319:",
    '"8319:8319"',
    "allowedTCPPorts = [ 8319 ]",
):
    require(forbidden not in module,
            f"OmniRoute module must not touch port 8319 / disable hermes-router: {forbidden!r}")

for needle in (
    "127.0.0.1:8320:8320",
    "OMNIROUTE_API_KEY=${config.sops.placeholder.omniroute_api_key}",
    "ROUTER_API_KEY=${config.sops.placeholder.omniroute_api_key}",
    "REQUIRE_API_KEY=true",
    "users.users.omniroute = {",
    "isSystemUser = true;",
    # The unit mirrors the existing Honcho container-supervisor
    # pattern (`modules/ai/honcho.nix:honcho-local`). It runs as
    # root because the docker CLI needs `/root/.docker/config.json`
    # and the docker socket; the inner container is already sandboxed
    # by Docker's own user-namespace + the `--user 984:100` mapping.
    # We assert the *current* shape of the unit, not a generic
    # hardened-service template.
    'Type = "exec";',
    "--user",
    "984:100",
    "ExecStartPre",
    '"${pkgs.docker}/bin/docker" "rm" "-f" "omniroute"',
    "sha256:92c768c56e2de32c51a0621ef182835018b00b288c9bb235c5c5e4514658c1a1",
):
    require(needle in module, f"missing staged module contract: {needle}")

# 4. Sops contract: reuse the existing key, do not add a new sops entry.
require("hermes_router_proxy_api_key" in module,
        "module must reuse sops key 'hermes_router_proxy_api_key'")
require("sopsFile" in module and "hermes-router.yaml" in module,
        "module must read sops from the existing hermes-router.yaml")

# 5. Legacy hermes-router module is still importable (rollback target).
require("hermes-router.service" in router,
        "legacy hermes-router module should still declare its service as a rollback target")

# 6. The test must be wired into flake.nix's `checks.x86_64-linux.regressions`.
require("tests/server-omniroute-regressions.py" in flake,
        "regression test must be wired into flake.nix's checks.x86_64-linux.regressions")

print("OmniRoute staged module (digest pin, sops reuse, 8320-only, no hermes-router override): PASS")
