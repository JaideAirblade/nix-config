#!/usr/bin/env python3
"""Regressions for server-only Hermes Router and pinned skill deployment."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "hosts/UwU-Server/ai/hermes-router.nix"
LOCAL_STACK = ROOT / "hosts/UwU-Server/ai/honcho.nix"
ROUTER_PATCH = ROOT / "hosts/UwU-Server/ai/patches/hermes-router-disable-admin-surfaces.patch"
ROUTER_MINIMAX_PATCH = ROOT / "hosts/UwU-Server/ai/patches/hermes-router-minimax-provider.patch"
MATH_PATCH = ROOT / "hosts/UwU-Server/ai/patches/math-via-code-secure-tempdir.patch"
MINIMAX_IMAGE_PATCH = ROOT / "hosts/UwU-Server/ai/patches/minimax-image-managed-media-only.patch"
MINIMAX_VIDEO_PATCH = ROOT / "hosts/UwU-Server/ai/patches/minimax-video-managed-media-only.patch"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(MODULE.exists(), "UwU-Server Hermes Router module is missing")
require(ROUTER_PATCH.exists(), "reviewed router admin-surface patch is missing")
require(ROUTER_MINIMAX_PATCH.exists(), "router MiniMax provider patch is missing")
require(MATH_PATCH.exists(), "reviewed math skill temp-directory patch is missing")
require(MINIMAX_IMAGE_PATCH.exists(), "reviewed MiniMax image plugin patch is missing")
require(MINIMAX_VIDEO_PATCH.exists(), "reviewed MiniMax video plugin patch is missing")
source = MODULE.read_text(encoding="utf-8")

for needle in (
    'repo = "Hermes-router";',
    'rev = "cc7ef00b5750416376b33c919406055d70275f9f";',
    'hash = "sha256-O7YyUK4V9y60Tcj/VkrWzE1pQOQllHUw91rlUE096i8=";',
    'repo = "hermes-skill-math-via-code";',
    'rev = "35ad332ae18aea7623df2829df9c4003cba88ba4";',
    'hash = "sha256-qJJxQ+E8RkYwEPX93tG783Ixq+gqYwpW7mYjXLp1o04=";',
    'repo = "hermes-plugin-minimax-image";',
    'rev = "5a07a0f67d74a67ac426d7b901f8bfc60f28951c";',
    'hash = "sha256-Tj8m243EmV8legIQyfGvGkfIze5l7bAtbCWQ5gyqhxA=";',
    'repo = "hermes-plugin-minimax-video";',
    'rev = "759bec0f124c50e868facc8da5e6cf054403d761";',
    'hash = "sha256-fWwmtBubTvxQ2LZyftGwWD0IzC1nY6EIl0kBqUrtKd0=";',
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
    'restartUnits = [ "hermes-router.service" ];',
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
    "./patches/hermes-router-minimax-provider.patch",
    "./patches/math-via-code-secure-tempdir.patch",
    "./patches/minimax-image-managed-media-only.patch",
    "./patches/minimax-video-managed-media-only.patch",
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

minimax_provider_patch = ROUTER_MINIMAX_PATCH.read_text(encoding="utf-8")
for needle in (
    '"name":     "minimax",',
    'os.environ.get("MINIMAX_BASE_URL", "https://api.minimax.io/v1")',
    'os.environ.get("MINIMAX_MODEL", "MiniMax-M3")',
    '_keys_for("minimax", "MINIMAX_API_KEYS")',
    '"minimax": 68, "nemotron": 99,',
    '"minimax",\n',
    '"name":     "nemotron",',
    'os.environ.get("NEMOTRON_BASE_URL", "http://127.0.0.1:8080/v1")',
    'os.environ.get("NEMOTRON_MODEL", "unsloth/Nemotron-3-Nano-30B-A3B")',
):
    require(needle in minimax_provider_patch, f"router MiniMax provider patch incomplete: {needle}")

math_patch = MATH_PATCH.read_text(encoding="utf-8")
for needle in ("TemporaryDirectory", "chmod(0o600)", "subprocess.run"):
    require(needle in math_patch, f"math skill patch lacks secure temp handling: {needle}")
math_added = "\n".join(
    line[1:] for line in math_patch.splitlines() if line.startswith("+") and not line.startswith("+++")
)
require("tempfile.gettempdir()" not in math_added, "math skill patch must not add predictable shared temp paths")

for plugin_patch_path in (MINIMAX_IMAGE_PATCH, MINIMAX_VIDEO_PATCH):
    plugin_patch = plugin_patch_path.read_text(encoding="utf-8")
    for needle in (
        "get_hermes_home",
        "_managed_media_roots",
        "_open_directory_nofollow",
        "O_DIRECTORY",
        "dir_fd=directory_descriptor",
        "_require_exact_image_container",
        "PNG contains trailing data",
        "_MAX_IMAGE_PIXELS",
        "decoded.load()",
        ".relative_to(",
        "st_nlink != 1",
        'src.startswith("data:image/")',
        "Unsupported local image type",
        "Unsupported local image content",
    ):
        require(needle in plugin_patch, f"{plugin_patch_path.name} lacks local-upload hardening: {needle}")

video_patch = MINIMAX_VIDEO_PATCH.read_text(encoding="utf-8")
video_added = "\n".join(
    line[1:] for line in video_patch.splitlines() if line.startswith("+") and not line.startswith("+++")
)
require("MINIMAX_PAYG_KEY" not in video_added, "video plugin patch must not preserve the mismatched credential name")
require("MINIMAX_API_KEY" in video_added, "video plugin patch must standardize on MINIMAX_API_KEY")

image_patch = MINIMAX_IMAGE_PATCH.read_text(encoding="utf-8")
image_added = "\n".join(
    line[1:] for line in image_patch.splitlines() if line.startswith("+") and not line.startswith("+++")
)
for label, added in (("image", image_added), ("video", video_added)):
    require(
        "never redirect bearer credentials" in added,
        f"{label} plugin must force the official MiniMax API endpoint",
    )
    require(
        "never redirect credential selection" in added,
        f"{label} plugin must force MINIMAX_API_KEY credential selection",
    )
require("save_url_image(" not in image_added, "image plugin must not auto-download untrusted response URLs")
require("save_url_video(" not in video_added, "video plugin must not auto-download untrusted response URLs")

for needle in (
    'mathSkillPath = "/home/luna/.hermes/skills/software-development/math-via-code";',
    '"${mathViaCodeSource}/skills/math-via-code"',
    "preflight_managed_symlink() {",
    "preflight_target_parent() {",
    "is_manifested_target() {",
    "record_managed_targets() {",
    'refusing symlinked parent for managed Hermes target',
    'current_target="$(readlink -f -- "$target" || true)"',
    'expected_target="$(readlink -f -- "$source")"',
    'if [[ "$current_target" != "$expected_target" ]]; then',
    "# Preflight every managed target before any filesystem mutation.",
    "# Mutate only after every target has passed preflight.",
    'systemd.services.hermes-server-extensions = {',
    "system.build.hermesServerExtensionsInstaller = installHermesServerExtensions;",
    'User = "luna";',
    'Environment = "HOME=/home/luna";',
    'ReadWritePaths = [ "/home/luna/.hermes" ];',
):
    require(needle in source, f"missing server extension deployment behavior: {needle}")

preflight_marker = source.index("# Preflight every managed target before any filesystem mutation.")
mutation_marker = source.index("# Mutate only after every target has passed preflight.")
require(preflight_marker < mutation_marker, "all managed targets must be preflighted before mutation")

for needle in (
    'minimaxImagePluginPath = "/home/luna/.hermes/plugins/minimax-image";',
    'minimaxVideoPluginPath = "/home/luna/.hermes/plugins/minimax-video";',
    'localMinimaxImagePluginPath = "/home/luna/.hermes/profiles/local/plugins/minimax-image";',
    'localMinimaxVideoPluginPath = "/home/luna/.hermes/profiles/local/plugins/minimax-video";',
    'hermes plugins enable minimax-image',
    'hermes plugins enable minimax-video',
    'hermes config set image_gen.minimax.key_env MINIMAX_API_KEY',
    'hermes config set video_gen.minimax.key_env MINIMAX_API_KEY',
    'HERMES_HOME=/home/luna/.hermes/profiles/local',
):
    require(needle in source, f"missing declarative server MiniMax plugin behavior: {needle}")

require(
    "hermes config set image_gen.provider minimax" not in source,
    "MiniMax installation must not replace the selected image provider",
)
require(
    "hermes config set video_gen.provider minimax" not in source,
    "MiniMax installation must not select an unavailable video provider",
)

for needle in (
    "mnemosynePluginSource",
    'localMnemosynePluginPath = "/home/luna/.hermes/profiles/local/plugins/mnemosyne";',
    'hermes config set memory.provider mnemosyne',
    'after = [ "hermes-local-profile.service" ];',
    'requires = [ "hermes-local-profile.service" ];',
):
    require(needle in source, f"missing declarative server Mnemosyne behavior: {needle}")

require(
    'if [[ -f /home/luna/.hermes/config.yaml ]]; then' not in source,
    "default Mnemosyne selection must not be skipped on a fresh Hermes home",
)

local_stack = LOCAL_STACK.read_text(encoding="utf-8")
require("provider: mnemosyne" in local_stack, "managed local profile must select Mnemosyne")
require("provider: honcho" not in local_stack, "managed local profile must not revert to Honcho")
require("http://127.0.0.1:8319" not in source, "default Hermes inference must not switch to the unprovisioned router")

print("server Hermes pins, hardened router, reviewed skills/plugins, and Mnemosyne persistence: PASS")
