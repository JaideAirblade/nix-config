#!/usr/bin/env python3
"""Regression policy for private-device users, passwords, and sudo."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ROLE = ROOT / "modules/users/private-accounts.nix"
UWU = ROOT / "hosts/UwU/default.nix"
SERVER = ROOT / "hosts/UwU-Server/default.nix"
WORK = ROOT / "hosts/TSBW-W01800/default.nix"
UWU_USERS = ROOT / "hosts/UwU/users/users.nix"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(ROLE.is_file(), "private-account role module is missing")
role = ROLE.read_text()
uwu = UWU.read_text()
server = SERVER.read_text()
work = WORK.read_text()
uwu_users = UWU_USERS.read_text()

require("nixos.modules.privateAccounts" in role, "privateAccounts role is not declared")
require(
    'sops.secrets.jaide_password_hash' in role
    and "neededForUsers = true;" in role,
    "Jaide password hash is not an early sops-nix user secret",
)
require(
    'secrets/private/accounts.yaml' in role,
    "shared private-device password file is not selected",
)
require(
    re.search(
        r"hashedPasswordFile\s*=\s*config\.sops\.secrets\.jaide_password_hash\.path;",
        role,
    )
    is not None,
    "Jaide does not consume the SOPS hash with hashedPasswordFile",
)
require(
    "users.mutableUsers = false;" in role,
    "private-device passwords are not declaratively enforced on existing users",
)
require(
    re.search(r'users\.users\.root\.hashedPassword\s*=\s*"!";', role) is not None,
    "root is not declaratively locked",
)
require('users.users."luna"' in role, "Luna automation account is missing")
require(
    "isSystemUser = true;" in role
    and 'home = "/var/lib/luna";' in role
    and "createHome = true;" in role,
    "Luna is not a hidden system automation account with a persistent home",
)
require(
    re.search(
        r'openssh\.authorizedKeys\.keys\s*=\s*\[\s*"restrict ssh-ed25519\s+',
        role,
        re.S,
    )
    is not None,
    "Luna does not have a forwarding-restricted dedicated SSH public key",
)
require(
    re.search(r'extraGroups\s*=\s*\[[^]]*"wheel"', role, re.S) is not None,
    "Luna is not in wheel",
)
require(
    "wheelNeedsPassword = true;" in role,
    "wheel password requirement is not kept for Jaide",
)
require(
    re.search(
        r'users\s*=\s*\[\s*"luna"\s*\].*?command\s*=\s*"ALL";.*?"NOPASSWD"',
        role,
        re.S,
    )
    is not None,
    "Luna does not have an explicit account-scoped passwordless sudo rule",
)
require(
    "security.pam.u2f" in role
    and re.search(
        r"security\.pam\.u2f\s*=\s*\{\s*enable\s*=\s*false;", role, re.S
    )
    is not None
    and "control = \"sufficient\";" in role
    and "greetd.u2f.enable = true;" in role
    and "login.u2f.enable = true;" in role
    and "sudo.u2f.enable = false;" in role,
    "U2F is not scoped exclusively to login services with password-only privilege elevation",
)
require(
    "config.nixos.modules.privateAccounts" in uwu
    and "config.nixos.modules.privateAccounts" in server,
    "privateAccounts is not imported by both private hosts",
)
require(
    "config.nixos.modules.privateAccounts" not in work,
    "private account policy leaked onto the work host",
)
require(
    "sops.secrets.luna_ssh_private_key" in uwu_users
    and "secrets/UwU/luna-agent.yaml" in uwu_users
    and 'owner = "jaide";' in uwu_users
    and 'mode = "0600";' in uwu_users,
    "the Luna controller key is not SOPS-deployed only on UwU",
)
require(
    "LUNA_SSH_IDENTITY" in uwu_users,
    "UwU does not publish the runtime Luna identity path to the agent",
)

violations: list[str] = []
for path in ROOT.rglob("*.nix"):
    text = path.read_text()
    if re.search(r'\binitialPassword\s*=', text):
        violations.append(f"{path.relative_to(ROOT)}: initialPassword")
    if re.search(r'\bpassword\s*=\s*"', text):
        violations.append(f"{path.relative_to(ROOT)}: plaintext password")
    for match in re.finditer(r'\bhashedPassword\s*=\s*"([^"]*)"', text):
        if match.group(1) != "!":
            violations.append(f"{path.relative_to(ROOT)}: literal password hash")
require(not violations, "unsafe password assignments: " + ", ".join(violations))

print("private account regressions: PASS")
