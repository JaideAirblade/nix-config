#!/usr/bin/env python3
"""Static regressions for UwU-Server's local inference/Honcho rollback stack."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "hosts/UwU-Server/ai/honcho.nix"
FLAKE = ROOT / "flake.nix"
LOCK = ROOT / "flake.lock"
REVIEW = ROOT / "tests/review-regressions.sh"


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def require(text: str, needle: str, message: str) -> None:
    if needle not in text:
        fail(message)


def require_condition(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def require_pattern(text: str, pattern: str, message: str) -> None:
    if not re.search(pattern, text, re.MULTILINE | re.DOTALL):
        fail(message)


def reject(text: str, pattern: str, message: str) -> None:
    if re.search(pattern, text, re.MULTILINE):
        fail(message)


if not MODULE.is_file():
    fail("UwU-Server local Honcho module is missing")

module = MODULE.read_text(encoding="utf-8")
flake = FLAKE.read_text(encoding="utf-8")
lock = json.loads(LOCK.read_text(encoding="utf-8"))
review = REVIEW.read_text(encoding="utf-8")

# Reproducible upstream/model selection.
require(flake, "github:plastic-labs/honcho/v3.0.12", "Honcho v3.0.12 is not pinned")
commit_match = re.search(r'honchoCommit\s*=\s*"([0-9a-f]{40})";', module)
require_condition(commit_match is not None, "Honcho source commit guard is missing")
assert commit_match is not None
honcho_commit = commit_match.group(1)
honcho_node = lock["nodes"]["root"]["inputs"]["honcho"]
locked_honcho_commit = lock["nodes"][honcho_node]["locked"]["rev"]
require_condition(
    honcho_commit == locked_honcho_commit,
    "Honcho source commit guard does not match the locked input revision",
)
require_condition(
    honcho_commit == "5ad22840d829878f9ac4d13e9538e5fef216c97e",
    "Honcho source commit changed unexpectedly",
)
require_pattern(
    module,
    r"assertion\s*=\s*inputs\.honcho\.rev\s*==\s*honchoCommit;",
    "evaluated Honcho input revision assertion is missing",
)
require(module, "Nemotron-3-Nano-30B-A3B-UD-Q4_K_XL.gguf", "selected Nemotron quant is missing")
require(module, "627f5b04aedc97f967332f331bd75b7a4ed2f33ca83e6ee74b44235cc1887890", "Nemotron SHA-256 is missing")
require(module, "Qwen3-Embedding-4B-Q8_0.gguf", "embedding model is missing")
require(module, "b60ae5ce2dd6a0b77f82cadf21def1f310a3e10cde380ad0081b07a9d416949d", "embedding SHA-256 is missing")

# Unsloth's model-specific tool-calling settings. Allow the Nix formatter to
# place adjacent list elements on separate lines without weakening the check.
for flag, value in (("ctx-size", "65536"), ("temp", "0.6"), ("top-p", "0.95")):
    require_pattern(module, rf'"--{re.escape(flag)}"\s+"{re.escape(value)}"', f"Nemotron flag missing: --{flag} {value}")
require(module, "context_length: 65536", "Hermes local profile must advertise the matching 64K context")
require(module, '"--jinja"', "Nemotron flag missing: --jinja")
require_condition(
    re.search(r'qwen-embedding-local = .*?"--special"', module, re.MULTILINE | re.DOTALL) is None,
    "embedding production API exposes special chat tokens",
)
reject(module, r'"--prio"\s+"3"', "Nemotron may not request SCHED_FIFO/90 under RestrictRealtime")

# Local-only network boundary. Database and Redis must not publish host ports.
require(module, '"127.0.0.1:8000:8000"', "Honcho API is not loopback-bound")
require(module, 'networking.firewall.interfaces.honcho0.allowedTCPPorts = [ 8080 8082 ];', "Honcho-bridge-only LLM firewall rule is missing")
require(module, 'driver_opts."com.docker.network.bridge.name" = "honcho0";', "deterministic Honcho bridge name is missing")
for exposed in ('"5432:5432"', '"6379:6379"', '"0.0.0.0:8000:8000"'):
    reject(module, re.escape(exposed), f"forbidden host exposure present: {exposed}")
reject(module, r"networking\.firewall\.allowedTCPPorts\s*=.*(?:8000|8080|8082|5432|6379)", "AI ports leaked into the global firewall")

# Runtime-generated credentials and container hardening.
require(module, 'openssl rand -hex 32', "runtime database secret generation is missing")
require(module, 'AUTH_USE_AUTH=false', "loopback-only auth policy is not explicit")
require(module, 'cap_drop = [ "ALL" ];', "Honcho application containers do not drop capabilities")
require(module, 'security_opt = [ "no-new-privileges:true" ];', "Honcho application containers permit privilege escalation")
require(module, 'pull_policy = "never";', "local Honcho image may be pulled from an untrusted registry")
reject(module, r'POSTGRES_HOST_AUTH_METHOD\s*=\s*"?trust', "PostgreSQL trust authentication is enabled")

redis_match = re.search(r"\n\s+redis = \{(?P<body>.*?)\n\s+\};\n\n\s+init =", module, re.DOTALL)
require_condition(redis_match is not None, "Redis Compose service block is missing")
assert redis_match is not None
redis = redis_match.group("body")
require(
    redis,
    'image = "redis:8.2@sha256:616bb446d5db225ddf786052834279e7c7222c48694d4451e8af22b8f5953b28";',
    "Redis UID/GID assumptions are not bound to the reviewed image digest",
)
require(redis, 'cap_drop = [ "ALL" ];', "Redis does not drop all capabilities by default")
require(
    redis,
    'user = "999:999";',
    "Redis is not pinned to the image's unprivileged redis UID/GID",
)
reject(redis, r"cap_add\s*=", "Redis should not receive capabilities when running as UID/GID 999")
require(redis, 'security_opt = [ "no-new-privileges:true" ];', "Redis permits privilege escalation")

require_pattern(
    module,
    r'local-ai-models\s*=\s*\{.*?RestrictAddressFamilies\s*=\s*\[\s*"AF_INET"\s*"AF_INET6"\s*"AF_NETLINK"\s*"AF_UNIX"\s*\];',
    "model downloader lacks AF_NETLINK required by aria2/c-ares DNS",
)

# Local embeddings must use immutable 2560-dimensional pgvector bootstrap.
# (Upgraded from 1024 on 2026-08-05 when the local embedder switched from
# Qwen3-Embedding 0.6B → 4B; same model family, but 4B emits 2560-dim vectors.)
for setting in (
    "EMBEDDING_VECTOR_DIMENSIONS=2560",
    "EMBEDDING_MODEL_CONFIG__DIMENSIONS_MODE=never",
    "scripts/configure_embeddings.py --yes",
):
    require(module, setting, f"embedding bootstrap setting missing: {setting}")
require(
    module,
    'command = [ "/app/.venv/bin/python scripts/provision_db.py && /app/.venv/bin/python scripts/configure_embeddings.py --yes" ];',
    "Honcho init shell program is not preserved as one argv element",
)

# Operational guardrails.
for service in ("local-ai-models", "nemotron-local", "qwen-embedding-local", "honcho-local", "honcho-backup"):
    require(module, service, f"required service is missing: {service}")
require(module, 'users.users.jaide.extraGroups', "Docker-group exclusion assertion has no evaluated user input")
require(module, 'assertion = !(builtins.elem "docker"', "Jaide Docker-group exclusion assertion is missing")
require(module, 'pkgs.llama-cpp-vulkan', "Vulkan llama.cpp package is not selected")
require(module, "qwen3-embedding-4b", "managed local profile is not repointed to the 4B alias")
require(module, 'provider: mnemosyne', "managed Hermes profile does not select Mnemosyne memory")
reject(module, r'^\s+provider: honcho$', "managed Hermes profile still selects Honcho memory")
require(module, 'baseUrl = "http://127.0.0.1:8000";', "profile-local Honcho URL is missing")
require(module, 'hosts.hermes_local', "named Hermes profile has no isolated Honcho host block")
require(module, 'hermes-local-profile = {', "managed Hermes local profile service is missing")
require(module, 'ReadWritePaths = [ "/home/luna/.hermes" ];', "Hermes profile installer is not home-write scoped")
require(module, '"d /home/luna/.hermes 0700 luna luna -"', "Hermes profile root is not created declaratively")
require(module, '"d /home/luna/.hermes/profiles 0700 luna luna -"', "Hermes profiles root is not created declaratively")
require(module, 'TimeoutStartSec = "2h";', "large model download has no explicit start timeout")
require_pattern(module, r'local-ai-models = \{.*?RemainAfterExit = true;.*?Restart = "on-failure";', "model downloader is not a retained, retrying prerequisite")
require(module, 'runtimeInputs = [ pkgs.coreutils pkgs.docker-compose pkgs.findutils ];', "backup does not carry its Compose binary")
require(module, 'docker-compose \\', "backup does not invoke standalone docker-compose")
require(
    module,
    "path = [ pkgs.docker pkgs.docker-buildx pkgs.docker-compose ];",
    "Honcho service path does not retain the explicit Buildx plugin",
)
require_pattern(
    module,
    r'ExecStartPre = \[.*?\$\{pkgs\.docker\}/bin/docker.*?"buildx".*?"build".*?"--builder".*?"default".*?"--load".*?"--file".*?\(toString honchoDockerfile\).*?"--tag".*?honchoImage.*?\(toString inputs\.honcho\).*?\];',
    "Honcho image is not built explicitly with Docker Buildx and the digest-pinned Dockerfile",
)
require_pattern(
    module,
    r'ExecStart = lib\.escapeShellArgs \[.*?"up".*?"--detach".*?"--no-build".*?"--remove-orphans".*?"--wait".*?\];',
    "Honcho Compose startup does not explicitly prohibit policy-driven builds",
)
require_condition(
    re.search(r'ExecStart = lib\.escapeShellArgs \[.*?"up".*?"--build"', module, re.MULTILINE | re.DOTALL) is None,
    "Honcho Compose startup still requests the legacy implicit build path",
)
require(review, "local-honcho-regressions.py", "aggregate regression runner does not invoke the Honcho test")

print("local Honcho regressions: PASS")
