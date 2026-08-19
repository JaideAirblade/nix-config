#!/usr/bin/env python3
"""Regressions for the Luna-Server hermes-gateway user-scope service.

Asserts that:
  - hosts/Luna-Server/ai/hermes-gateway.nix exists
  - it declares a user-scope systemd service named hermes-gateway
  - it targets luna (ConditionUser = "luna")
  - ExecStart uses pkgs.hermes-agent (NOT an imperatively installed binary)
  - it sets RestrictAddressFamilies to include AF_INET + AF_INET6
    (gateway needs to reach Telegram/Discord/WhatsApp over HTTPS)
  - it does NOT set MemoryDenyWriteExecute=true
    (Python+node sub-processes would crash)
  - it includes /home/luna/.hermes in ReadWritePaths
    (gateway needs to write session state)

The module is auto-imported by flake.nix's collectModules helper
(because every .nix file under ./hosts/... is picked up), so this test
only needs to assert the module contents are right, not that flake.nix
references it.

If someone refactors the file away or renames it without updating the
test, this regression will catch it.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "hosts/Luna-Server/ai/hermes-gateway.nix"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(MODULE.exists(), "Luna-Server hermes-gateway module is missing")

source = MODULE.read_text(encoding="utf-8")

# 1. Service is declared at user scope, named hermes-gateway
require(
    re.search(r"systemd\.user\.services\.hermes-gateway\s*=", source) is not None,
    "hermes-gateway is not declared as a systemd.user.services entry",
)

# 2. Targets luna only (single-user scope)
require(
    re.search(r'ConditionUser\s*=\s*"luna"', source) is not None,
    "hermes-gateway must be conditioned to luna's session",
)

# 3. Uses the nixpkgs hermes-agent (declarative; not a hand-installed binary)
require(
    re.search(r"\$\{pkgs\.hermes-agent\}/bin/hermes\s+gateway\s+run", source) is not None,
    "ExecStart must use pkgs.hermes-agent — no imperatively installed binaries",
)

# 4. Network access for HTTPS out to messaging platforms
require(
    re.search(r'RestrictAddressFamilies\s*=\s*\[\s*"AF_UNIX"\s+"AF_INET"\s+"AF_INET6"\s*\]', source)
    is not None,
    "RestrictAddressFamilies must include AF_INET + AF_INET6 (gateway reaches Telegram/Discord/etc.)",
)

# 5. Does NOT set MemoryDenyWriteExecute (would break Python/node children).
# Strip line-comments first so the explanatory comment in the .nix file
# doesn't trip the test.
non_comment_source = "\n".join(
    line for line in source.split("\n")
    if not line.lstrip().startswith("#")
)
require(
    re.search(r"MemoryDenyWriteExecute\s*=\s*true", non_comment_source) is None,
    "MemoryDenyWriteExecute=true would crash hermes CLI's Python+node subprocesses",
)

# 6. ReadWritePaths must include ~/.hermes so the gateway can write config + sessions
require(
    re.search(r'ReadWritePaths\s*=\s*\[[^\]]*"/home/luna/\.hermes"', source) is not None,
    "ReadWritePaths must include /home/luna/.hermes (gateway writes session state)",
)

# 7. Hardening baseline (mirrors hermes-router) — guard against silent regressions
for token in (
    "NoNewPrivileges = true;",
    "PrivateDevices = true;",
    "PrivateTmp = true;",
    "ProtectSystem = \"strict\";",
    "RestrictNamespaces = true;",
    "LockPersonality = true;",
):
    require(token in source, f"missing hardening line: {token.strip()}")

print("PASS  server-hermes-gateway-regressions.py")
