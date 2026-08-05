#!/usr/bin/env python3
"""Regressions for server-only Hermes Router and pinned skill deployment."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "hosts/UwU-Server/ai/hermes-router.nix"
LOCAL_STACK = ROOT / "hosts/UwU-Server/ai/honcho.nix"
ROUTER_PATCH = ROOT / "hosts/UwU-Server/ai/patches/hermes-router-disable-admin-surfaces.patch"
MATH_PATCH = ROOT / "hosts/UwU-Server/ai/patches/math-via-code-secure-tempdir.patch"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(MODULE.exists(), "UwU-Server Hermes Router module is missing")
require(ROUTER_PATCH.exists(), "reviewed router admin-surface patch is missing")
require(MATH_PATCH.exists(), "reviewed math skill temp-directory patch is missing")
source = MODULE.read_text(encoding="utf-8")

for needle in (
    'repo = "Hermes-router";',
    'rev = "cc7ef00b5750416376b33c919406055d70275f9f";',
    'hash = "sha256-O7YyUK4V9y60Tcj/VkrWzE1pQOQllHUw91rlUE096i8=";',
    'repo = "hermes-skill-math-via-code";',
    'rev = "35ad332ae18aea7623df2829df9c4003cba88ba4";',
    'hash = "sha256-qJJxQ+E8RkYwEPX93tG783Ixq+gqYwpW7mYjXLp1o04=";',
):
    require(needle in source, f"missing immutable source pin: {needle}")

for needle in (
    "python312.withPackages",
    "ps.flask",
    "ps.requests",
    "ps.waitress",
    "ps.tiktoken",
    'users.users.hermes-router = {',
    "isSystemUser = true;",
    'users.groups.hermes-router = { };',
    "sops.secrets.hermes_router_proxy_api_key",
    "sops.templates.hermes-router-env",
    'HOST = "127.0.0.1";',
    'PORT = "8319";',
    'CACHE_TTL_SECONDS = "0";',
    'CACHE_PERSIST = "0";',
    'AUTO_DISCOVER_MODELS = "0";',
    'HERMES_ADMIN_SURFACES = "0";',
    'REQUEST_LOG_SIZE = "0";',
    'METRICS_REQUIRE_AUTH = "1";',
    'systemd.services.hermes-router = {',
    'User = "hermes-router";',
    'Group = "hermes-router";',
    'StateDirectory = "hermes-router";',
    'ProtectSystem = "strict";',
    "ProtectHome = true;",
    "NoNewPrivileges = true;",
    'RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];',
    'CapabilityBoundingSet = "";',
):
    require(needle in source, f"missing hardened router behavior: {needle}")

require("allowedTCPPorts = [ 8319 ]" not in source, "router port must not be opened in the firewall")

for needle in (
    "pkgs.applyPatches",
    "./patches/hermes-router-disable-admin-surfaces.patch",
    "./patches/math-via-code-secure-tempdir.patch",
):
    require(needle in source, f"missing reviewed source patch wiring: {needle}")

router_patch = ROUTER_PATCH.read_text(encoding="utf-8")
for needle in (
    'HERMES_ADMIN_SURFACES',
    'request.path.startswith("/v1/config/")',
    'request.path.startswith("/v1/instances")',
    'request.path == "/dashboard"',
):
    require(needle in router_patch, f"router patch does not fail-close an unsafe surface: {needle}")

math_patch = MATH_PATCH.read_text(encoding="utf-8")
for needle in ("TemporaryDirectory", "chmod(0o600)", "subprocess.run"):
    require(needle in math_patch, f"math skill patch lacks secure temp handling: {needle}")
math_added = "\n".join(
    line[1:] for line in math_patch.splitlines() if line.startswith("+") and not line.startswith("+++")
)
require("tempfile.gettempdir()" not in math_added, "math skill patch must not add predictable shared temp paths")

for needle in (
    'mathSkillPath = "/home/jaide/.hermes/skills/software-development/math-via-code";',
    '"${mathViaCodeSource}/skills/math-via-code"',
    '[[ -e "$skill_path" && ! -L "$skill_path" ]]',
    'ln -sfnT "$skill_source" "$skill_path"',
    'systemd.services.hermes-server-extensions = {',
    'User = "jaide";',
    'Environment = "HOME=/home/jaide";',
    'ReadWritePaths = [ "/home/jaide/.hermes" ];',
):
    require(needle in source, f"missing server math skill deployment behavior: {needle}")

for needle in (
    "mnemosynePluginSource",
    'localMnemosynePluginPath = "/home/jaide/.hermes/profiles/local/plugins/mnemosyne";',
    'hermes config set memory.provider mnemosyne',
    'after = [ "hermes-local-profile.service" ];',
):
    require(needle in source, f"missing declarative server Mnemosyne behavior: {needle}")

local_stack = LOCAL_STACK.read_text(encoding="utf-8")
require("provider: mnemosyne" in local_stack, "managed local profile must select Mnemosyne")
require("provider: honcho" not in local_stack, "managed local profile must not revert to Honcho")
require("http://127.0.0.1:8319" not in source, "default Hermes inference must not switch to the unprovisioned router")

print("server Hermes pins, hardened router, math skill, and Mnemosyne persistence: PASS")
