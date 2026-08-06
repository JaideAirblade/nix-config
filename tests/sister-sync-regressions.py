#!/usr/bin/env python3
"""Regression policy for sister-sync cross-account read access.

Jaide (admin) and luna (automation) on the private devices (UwU, UwU-Server)
share group-readable access to /home/jaide so luna can read wallpapers, .config,
and other personalisation state to mirror Jaide's laptop onto UwU-Server and
to make state portable for trips (e.g. visiting family with a sibling setup).

The shape of the policy:
- jaide has a dedicated primary group `jaide` (not the system `users` group).
- /home/jaide is mode 0750 (group-readable, world-closed) and group-owned by `jaide`.
- luna is a member of the `jaide` group so the group-read bits admit her.
- The change is local to the two private hosts — work/print-server hosts
  must NOT receive it.
- A one-shot activation script migrates existing files inside /home/jaide
  from the old primary group (`users`, gid 100) to the new `jaide` group.
"""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

UWU_USERS = ROOT / "hosts/UwU/users/users.nix"
SERVER_USERS = ROOT / "hosts/UwU-Server/users/users.nix"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(UWU_USERS.is_file(), f"{UWU_USERS} is missing")
require(SERVER_USERS.is_file(), f"{SERVER_USERS} is missing")

uwu_users = UWU_USERS.read_text()
server_users = SERVER_USERS.read_text()

# Both private hosts must declare jaide's primary group as `jaide` so luna
# can read /home/jaide via group membership rather than the shared system
# `users` group. Using a dedicated group keeps the trust boundary explicit.
for label, text in (("UwU", uwu_users), ("UwU-Server", server_users)):
    require(
        re.search(
            r'users\.users\."jaide"\s*=\s*\{[^}]*group\s*=\s*"jaide";',
            text,
            re.S,
        )
        is not None,
        f"{label} does not declare jaide.group = \"jaide\"",
    )

# Both private hosts must declare jaide's home as group-readable so luna
# (a member of the `jaide` group) can read it for the sister-sync use case.
# Mode 0750 is the only acceptable value here — 0700 blocks luna, 0755
# exposes the home to the world, anything in between is wrong.
for label, text in (("UwU", uwu_users), ("UwU-Server", server_users)):
    require(
        re.search(
            r'users\.users\."jaide"\s*=\s*\{[^}]*homeMode\s*=\s*"0750";',
            text,
            re.S,
        )
        is not None,
        f"{label} does not declare jaide.homeMode = \"0750\"",
    )

# Both private hosts must add luna to the `jaide` group so the group-read
# bits actually admit her. The NixOS-idiomatic way is
# `users.groups.jaide.members = [ "luna" ]`.
for label, text in (("UwU", uwu_users), ("UwU-Server", server_users)):
    require(
        re.search(
            r'users\.groups\.jaide\.members\s*=\s*\[\s*"luna"\s*\];',
            text,
        )
        is not None,
        f"{label} does not add luna to the `jaide` group",
    )

# The sister-sync MUST NOT pollute the system `users` group with personal
# account membership — that group is shared by every service on the host
# (e.g. hermes-webui.group = "users"). luna on its own is fine because
# the sister-sync is private-host-only.
for label, text in (("UwU", uwu_users), ("UwU-Server", server_users)):
    require(
        'users.groups.users.members' not in text,
        f"{label} adds luna to the shared `users` group — must use the dedicated `jaide` group instead",
    )

# Both private hosts must declare the one-shot chown migration service so
# existing files inside /home/jaide are reachable too (not just the dir
# itself). The service must be idempotent — `-group 100` matches nothing
# once everything is migrated, so re-runs are no-ops.
for label, text in (("UwU", uwu_users), ("UwU-Server", server_users)):
    require(
        "migrate-jaide-home-group" in text
        and "-group 100" in text
        and "chown :jaide" in text,
        f"{label} does not declare the idempotent migrate-jaide-home-group service",
    )

# Work host (TSBW-W01800) must NOT receive the sister-sync change — it is
# an automation-only host with no jaide home to share.
WORK_USERS = ROOT / "hosts/TSBW-W01800/users/users.nix"
if WORK_USERS.is_file():
    work_users = WORK_USERS.read_text()
    require(
        'group = "jaide"' not in work_users,
        "work host (TSBW-W01800) unexpectedly declares jaide's primary group — sister-sync is private-host-only",
    )
    require(
        'homeMode = "0750"' not in work_users,
        "work host (TSBW-W01800) unexpectedly declares jaide.homeMode — sister-sync is private-host-only",
    )

# The change must be read-only for /home/jaide. luna MUST NOT be granted
# write/chown access to /home/jaide via any path. A "luna writes to
# /home/jaide" capability would be a trust-boundary violation — the
# sister-sync is a one-way read. Note: this is scoped to /home/jaide only;
# chowns that touch luna's own home or other unrelated paths are fine.
for label, text in (("UwU", uwu_users), ("UwU-Server", server_users)):
    require(
        "chown luna:/home/jaide" not in text
        and "chown -R luna /home/jaide" not in text
        and "luna:jaide /home/jaide" not in text,
        f"{label} grants luna write/chown access to /home/jaide — sister-sync must be read-only",
    )

print("sister-sync regressions: PASS")