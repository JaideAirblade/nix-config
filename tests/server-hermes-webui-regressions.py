#!/usr/bin/env python3
"""Regressions for server-only Hermes WebUI pinning and hardening.

The flake substitutes the actual on-disk path of the nixos-secrets input
into the SOPS_ROOT environment variable before invoking this script; the
test asserts that secrets/UwU-Server/hermes-webui.yaml exists there with
the hermes_webui_password key. Outside `nix build` (e.g. running the
script directly), fall back to scanning /nix/store for the same."""

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "hosts/UwU-Server/ai/hermes-webui.nix"
FLAKE = ROOT / "flake.nix"
SECRETS_REL = "secrets/UwU-Server/hermes-webui.yaml"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def resolve_sops_root() -> Path | None:
    """Return the secrets repo root, prefer the value injected via env."""
    sops_env = os.environ.get("SOPS_ROOT")
    if sops_env:
        return Path(sops_env)
    for d in Path("/nix/store").glob("*-source"):
        if (d / SECRETS_REL).exists():
            return d
    return None


require(MODULE.exists(), "UwU-Server Hermes WebUI module is missing")

source = MODULE.read_text(encoding="utf-8")
flake_source = FLAKE.read_text(encoding="utf-8")

# The upstream NixOS module must be imported from the hermes-webui flake
# input — without this import, `services.hermes-webui` is undefined and the
# build fails (regression on import wiring).
require(
    "inputs.hermes-webui.nixosModules.default" in source,
    "hermes-webui upstream NixOS module not imported",
)

# Pin: flake input must reference a specific commit, not a branch or
# unstable tag. Drift in upstream master has broken the build before due
# to Python 3.13/3.14 changes and asyncio APIs.
require(
    'url = "github:nesquena/hermes-webui/c35b0659fec1d0656c5fa069826ac545f13b5654";'
    in flake_source,
    "hermes-webui flake input must be pinned to a known-good commit",
)

# Network binding: must bind to the Tailscale IP only, never 0.0.0.0 or
# [::]. The whole point of this module is to keep the WebUI on the
# tailnet only — a 0.0.0.0 bind exposes it to whatever the firewall
# might let through.
require(
    'host = "100.102.183.94";' in source,
    "WebUI must be bound to the Tailscale IP of UwU-Server",
)
require(
    "openFirewall = false;" in source,
    "WebUI port must not be exposed via the NixOS firewall",
)
require(
    '"0.0.0.0"' not in source and '"::"' not in source,
    "WebUI must not bind to 0.0.0.0 or ::",
)

# Hermes state sharing: must reuse the system's hermes-agent (so it picks
# up the hermes-router provider and Mnemosyne memory) and read the same
# ~/.hermes directory as on-host sessions.
require(
    "agent.package = pkgs.hermes-agent;" in source,
    "WebUI must reuse pkgs.hermes-agent (carries Mnemosyne + hermes-router)",
)
require(
    'hermesHome = "/home/luna/.hermes";' in source,
    "WebUI must share /home/luna/.hermes with on-host Hermes sessions",
)

# User identity: must run as luna so it can read/write ~/.hermes without
# UNIX permission gymnastics. Mirrors hermes-server-extensions.
require('user = "luna";' in source, "WebUI must run as user luna")
require('group = "users";' in source, "WebUI must run as group users")

# Auth: must load the password from sops, never plaintext.
require(
    "sops.templates.hermes-webui-password" in source,
    "sops template for the WebUI password is missing",
)
require(
    "sops.secrets.hermes_webui_password" in source,
    "sops secret entry for the WebUI password is missing",
)
require(
    "HERMES_WEBUI_PASSWORD" in source,
    "WebUI password env var must be set",
)
require(
    'mode = "0400";' in source,
    "WebUI password file must be 0400",
)

# Hardening: must apply the same template as hermes-router. Keeps the
# service from reaching anything outside its own Hermes state.
require(
    "NoNewPrivileges = true;" in source,
    "WebUI must set NoNewPrivileges",
)
require(
    'ProtectHome = "read-only";' in source,
    "WebUI must set ProtectHome to read-only",
)
require(
    'ProtectSystem = "strict";' in source,
    "WebUI must set ProtectSystem to strict",
)
require(
    'RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];' in source,
    "WebUI must restrict address families to AF_INET/AF_INET6/AF_UNIX",
)
require(
    'CapabilityBoundingSet = "";' in source,
    "WebUI must drop all capabilities",
)
require(
    'ReadWritePaths = [' in source and '/home/luna/.hermes' in source,
    "WebUI must have a writable path for /home/luna/.hermes",
)

# Sanity: must NOT have fallen back to writing the password to /etc or
# anywhere world-writable.
require(
    "/etc/hermes-webui-password" not in source,
    "password must not be written to /etc",
)
require(
    "0777" not in source and "0666" not in source,
    "WebUI must not use world-writable permissions",
)

# Inversely — the file has to be present in the nixos-secrets repo,
# otherwise the rendered env file the service depends on will fail to
# materialize at boot and the service will silently fail to start.
# The flake exposes the secret repo under `inputs.nixos-secrets`, so
# its on-disk path is reachable via the SOPS_ROOT env var (set in the
# regressions check in flake.nix). When running this script directly,
# fall back to scanning /nix/store.
sops_root = resolve_sops_root()
require(
    sops_root is not None,
    "nixos-secrets input not found; SOPS_ROOT env var unset and no /nix/store/*-source contains hermes-webui.yaml",
)
assert sops_root is not None  # require() exits on False; narrow the type for LSP
password_file = sops_root / SECRETS_REL
require(
    password_file.exists(),
    "nixos-secrets must contain secrets/UwU-Server/hermes-webui.yaml",
)
require(
    "hermes_webui_password" in password_file.read_text(),
    "secrets/UwU-Server/hermes-webui.yaml must contain the hermes_webui_password key",
)

print("OK: hermes-webui module passes all regressions", file=sys.stderr)
