#!/usr/bin/env python3
"""Static regressions for UwU-Server's fully local Honcho stack."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "hosts/UwU-Server/ai/honcho.nix"
FLAKE = ROOT / "flake.nix"
REVIEW = ROOT / "tests/review-regressions.sh"


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def require(text: str, needle: str, message: str) -> None:
    if needle not in text:
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
review = REVIEW.read_text(encoding="utf-8")

# Reproducible upstream/model selection.
require(flake, "github:plastic-labs/honcho/v3.0.12", "Honcho v3.0.12 is not pinned")
require(module, "5ad22840d829878f9ac4d13e9538e5fef216c97e", "Honcho source commit guard is missing")
require(module, "Nemotron-3-Nano-30B-A3B-UD-Q4_K_XL.gguf", "selected Nemotron quant is missing")
require(module, "627f5b04aedc97f967332f331bd75b7a4ed2f33ca83e6ee74b44235cc1887890", "Nemotron SHA-256 is missing")
require(module, "Qwen3-Embedding-0.6B-Q8_0.gguf", "embedding model is missing")
require(module, "06507c7b42688469c4e7298b0a1e16deff06caf291cf0a5b278c308249c3e439", "embedding SHA-256 is missing")

# Unsloth's model-specific tool-calling settings. Allow the Nix formatter to
# place adjacent list elements on separate lines without weakening the check.
for flag, value in (("ctx-size", "32768"), ("temp", "0.6"), ("top-p", "0.95")):
    require_pattern(module, rf'"--{re.escape(flag)}"\s+"{re.escape(value)}"', f"Nemotron flag missing: --{flag} {value}")
for flag in ("jinja", "special"):
    require(module, f'"--{flag}"', f"Nemotron flag missing: --{flag}")
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

# Local embeddings must use immutable 1024-dimensional pgvector bootstrap.
for setting in (
    "EMBEDDING_VECTOR_DIMENSIONS=1024",
    "EMBEDDING_MODEL_CONFIG__DIMENSIONS_MODE=never",
    "scripts/configure_embeddings.py --yes",
):
    require(module, setting, f"embedding bootstrap setting missing: {setting}")

# Operational guardrails.
for service in ("local-ai-models", "nemotron-local", "qwen-embedding-local", "honcho-local", "honcho-backup"):
    require(module, service, f"required service is missing: {service}")
require(module, 'users.users.jaide.extraGroups', "Docker-group exclusion assertion has no evaluated user input")
require(module, 'assertion = !(builtins.elem "docker"', "Jaide Docker-group exclusion assertion is missing")
require(module, 'pkgs.llama-cpp-vulkan', "Vulkan llama.cpp package is not selected")
require(module, 'default: ${nemotronAlias}', "managed Hermes profile does not select Nemotron")
require(module, 'provider: honcho', "managed Hermes profile does not select Honcho memory")
require(module, 'baseUrl = "http://127.0.0.1:8000";', "profile-local Honcho URL is missing")
require(module, 'hosts.hermes_local', "named Hermes profile has no isolated Honcho host block")
require(module, 'hermes-local-profile = {', "managed Hermes local profile service is missing")
require(module, 'ReadWritePaths = [ "/home/jaide/.hermes" ];', "Hermes profile installer is not home-write scoped")
require(module, '"d /home/jaide/.hermes 0700 jaide users -"', "Hermes profile root is not created declaratively")
require(module, '"d /home/jaide/.hermes/profiles 0700 jaide users -"', "Hermes profiles root is not created declaratively")
require(module, 'TimeoutStartSec = "2h";', "large model download has no explicit start timeout")
require_pattern(module, r'local-ai-models = \{.*?RemainAfterExit = true;.*?Restart = "on-failure";', "model downloader is not a retained, retrying prerequisite")
require(module, 'runtimeInputs = [ pkgs.coreutils pkgs.docker-compose pkgs.findutils ];', "backup does not carry its Compose binary")
require(module, 'docker-compose \\', "backup does not invoke standalone docker-compose")
require(review, "local-honcho-regressions.py", "aggregate regression runner does not invoke the Honcho test")

print("local Honcho regressions: PASS")
