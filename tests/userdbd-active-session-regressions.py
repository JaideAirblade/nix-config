#!/usr/bin/env python3
"""Regression policy for `services.userdbd`.

WHY THIS TEST EXISTS
──────────────────────────────────────────────────────────────────────
NixOS 26.05 ships `services.userdbd.enable = false` by default. Without
the userdbd service, the `users.users.<name>.extraGroups` change only
takes effect for NEW sessions — a user who is logged in at the time the
declarative config is updated must log out and back in (or start a
fresh shell) before the kernel hands the new supplementary group to
child processes. systemd-userdbd propagates the change to the running
user@<uid>.service instance so the running session picks up new
groups without a logout.

The first concrete bug this test catches: the netbird-mesh role adds
`jaide` to the `netbird-mesh` group so the hardened daemon socket at
`/var/run/netbird-mesh/sock` (mode 0750) is reachable. Without
userdbd, an already-logged-in jaide keeps the old `Groups:` set in
their kernel creds and the GUI app keeps losing on the socket.

INVARIANTS
──────────────────────────────────────────────────────────────────────
- `services.userdbd.enable = true` is set in the shared `users` module
  so every host that pulls `nixos.modules.common` (which is all of
  them) gets it.
- `services.userdbd.enableSSHSupport` is OFF (we are not using OpenSSH
  userdb integration; it pulls in `security.enableWrappers` which is a
  bigger change).
- The module is reachable from at least one host's `nix eval`
  evaluation.

Repeats the dry-build gate via nix eval so a future refactor that
silently drops the option fails here, not at the next deploy.
"""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
USERS = ROOT / "modules/users/users.nix"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


# --- source-level assertions ------------------------------------------------

require(USERS.is_file(), "modules/users/users.nix is missing")
src = USERS.read_text()

require(
    "services.userdbd.enable" in src,
    "modules/users/users.nix does not declare services.userdbd.enable — "
    "without it, running sessions cannot pick up new extraGroups",
)
require(
    "services.userdbd.enable = true" in src,
    "services.userdbd.enable is not set to true (it must be `true`, not "
    "`lib.mkDefault true` — false default in NixOS 26.05 means mkDefault "
    "would inherit false)",
)
# NixOS-standard sandbox build users (nixbld1..32, UIDs 30001-30032) and
# `nobody` (UID 65534) trigger the userdbd high-UID warning by default.
# We have these by design; silence the warning so dry-build stays clean.
require(
    "services.userdbd.silenceHighSystemUsers = true" in src,
    "services.userdbd.silenceHighSystemUsers is not set to true — NixOS "
    "sandbox users (nixbld1..32, nobody) trigger a warning every dry-build "
    "without it.",
)
require(
    not re.search(r"enableSSHSupport\s*=\s*true", src),
    "services.userdbd.enableSSHSupport must NOT be true (it requires "
    "security.enableWrappers; we don't use OpenSSH userdb integration). "
    "If you want to allow it, update this test.",
)


# --- eval-level assertion ---------------------------------------------------
# `nix eval` from the flake root, picking any host that pulls common (all of
# them do). We use UwU specifically because it is the host that motivated
# this whole change (the netbird socket permission issue).

eval_cmd = [
    "nix", "--extra-experimental-features", "nix-command flakes",
    "eval", "--impure", "--json", "--expr",
    # JSON projection so the bool is serialisable.
    f"(builtins.getFlake (toString {ROOT})).nixosConfigurations.UwU.config.services.userdbd.enable",
]
r = subprocess.run(eval_cmd, capture_output=True, text=True, cwd=ROOT, timeout=300)
require(
    r.returncode == 0,
    "nix eval failed: " + r.stderr.strip()[:500],
)
value = json.loads(r.stdout)
require(
    value is True,
    f"services.userdbd.enable on UwU is {value!r}; expected True",
)


# --- coverage: every host that pulls common should get userdbd --------------
# The shared `modules/users/users.nix` is imported via
# `nixos.modules.common` by every host. Walk the four canonical host
# entry points and assert they all evaluate to `enable = true`.

for host in ("UwU", "Luna-Server", "TSBW-W01800", "Projet-Printserver"):
    r = subprocess.run(
        [
            "nix", "--extra-experimental-features", "nix-command flakes",
            "eval", "--impure", "--json", "--expr",
            f"(builtins.getFlake (toString {ROOT})).nixosConfigurations.{host}.config.services.userdbd.enable",
        ],
        capture_output=True, text=True, cwd=ROOT, timeout=300,
    )
    require(
        r.returncode == 0,
        f"nix eval for {host} failed: " + r.stderr.strip()[:500],
    )
    value = json.loads(r.stdout)
    require(
        value is True,
        f"services.userdbd.enable on {host} is {value!r}; expected True",
    )


print("userdbd (active-session group propagation) regressions: PASS")
