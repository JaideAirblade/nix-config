#!/usr/bin/env python3
"""Regression policy for private-device users, passwords, and sudo."""

from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ROLE = ROOT / "modules/users/private-accounts.nix"
UWU = ROOT / "hosts/UwU/default.nix"
SERVER = ROOT / "hosts/Luna-Server/default.nix"
WORK = ROOT / "hosts/TSBW-W01800/default.nix"
UWU_USERS = ROOT / "hosts/UwU/users/users.nix"
SERVER_USERS = ROOT / "hosts/Luna-Server/users/users.nix"
PRINTSERVER_USERS = ROOT / "hosts/Projet-Printserver/users/users.nix"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(ROLE.is_file(), "private-account role module is missing")
role = ROLE.read_text()
uwu = UWU.read_text()
server = SERVER.read_text()
work = WORK.read_text()
uwu_users = UWU_USERS.read_text()
server_users = SERVER_USERS.read_text()
printserver_users = PRINTSERVER_USERS.read_text()

require("nixos.modules.privateAccounts" in role, "privateAccounts role is not declared")
require(
    "nixos.modules.automationAccounts" in role,
    "automationAccounts role is not declared separately",
)
require(
    "imports = [ automationAccounts ];" in role,
    "privateAccounts does not compose the automation account role",
)
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
    "isNormalUser = true;" in role
    and "isSystemUser = true;" not in role
    and 'home = "/home/luna";' in role
    and "createHome = true;" in role
    and 'homeMode = "0700";' in role
    and "autoSubUidGidRange = false;" in role,
    "Luna is not a normal automation user with the standard /home/luna home",
)
for migration_guard in (
    'name = "migrate-luna-home";',
    "/var/backups/luna-home-before-standard-home.tar",
    'chmod 0600 "$backup"',
    "rsync -aHAX --numeric-ids",
    "rsync -aHAXnc --numeric-ids",
    "legacy Luna home retained for rollback",
):
    require(migration_guard in role, f"Luna legacy-home migration lacks: {migration_guard}")
require(
    "activationScripts.migrate-luna-home" not in role
    and "rm -rf /var/lib/luna" not in role
    and "mv -- /var/lib/luna /home/luna" not in role,
    "Luna legacy home is moved or deleted during activation",
)
require(
    re.search(
        r'extraGroups\s*=\s*\[[^]]*"wheel"[^]]*"networkmanager"', role, re.S
    )
    is not None,
    "Luna does not have wheel and NetworkManager access",
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
    role.count("restrict ssh-ed25519") == 2
    and "luna-agent@UwU" in role
    and "luna-agent@Luna-Server" in role,
    "Luna targets do not authorize distinct UwU and Luna-Server fleet identities",
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
    "config.nixos.modules.privateAccounts" not in work
    and "config.nixos.modules.automationAccounts" in work,
    "work host does not select automation access without the private password policy",
)
require(
    "sops.secrets.luna_ssh_private_key" in uwu_users
    and "secrets/UwU/luna-agent.yaml" in uwu_users
    and "sops.templates.luna_ssh_identity" in uwu_users
    and 'content = "${config.sops.placeholder.luna_ssh_private_key}\\n";' in uwu_users
    and 'mode = "0600";' in uwu_users,
    "the Luna controller key is not SOPS-deployed only on UwU",
)
require(
    re.search(
        r"LUNA_SSH_IDENTITY\s*=\s*\n\s*config\.sops\.templates\.luna_ssh_identity\.path;",
        uwu_users,
    )
    is not None,
    "UwU does not publish the newline-safe Luna identity template path",
)
require(
    "secrets/Luna-Server/luna-agent.yaml" in server_users
    and "sops.secrets.luna_server_ssh_private_key" in server_users
    and 'key = "luna_ssh_private_key";' in server_users
    and "sops.templates.luna_server_ssh_identity" in server_users
    and 'owner = "luna";' in server_users
    and 'group = "luna";' in server_users
    and 'mode = "0600";' in server_users
    and '"L+ /home/luna/.ssh/id_ed25519' in server_users,
    "Luna-Server does not deploy Luna's distinct fleet identity into /home/luna",
)
require(
    "users.mutableUsers = false;" in printserver_users,
    "print server local users are not declaratively managed",
)

# Reject imperative lpadmin guidance in every tracked textual file, including
# generated shell snippets and documentation. Build sandboxes omit .git, so
# fall back to the already-filtered source tree there.
try:
    tracked_output = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "-z"],
        check=True,
        capture_output=True,
    ).stdout
    tracked_paths = [ROOT / path.decode() for path in tracked_output.split(b"\0") if path]
except (FileNotFoundError, subprocess.CalledProcessError):
    tracked_paths = [path for path in ROOT.rglob("*") if path.is_file()]

user_command_pattern = re.compile(
    r"(?<![A-Za-z0-9_.-])user" + r"mod(?![A-Za-z0-9_.-])",
    re.IGNORECASE,
)
lpadmin_group_pattern = re.compile(
    r"(?:(?<![A-Za-z0-9_.-])lpadmin|"
    r"(?<![A-Za-z0-9_.-])(?:-G|-aG)lpadmin)"
    r"(?![A-Za-z0-9_.-])",
    re.IGNORECASE,
)


def has_ephemeral_lpadmin_edit(text: str) -> bool:
    """Reject logical lines coupling the account editor to the print-admin group."""
    logical_lines: list[str] = []
    pending = ""
    for physical_line in text.splitlines(keepends=True):
        has_newline = physical_line.endswith("\n")
        line = physical_line[:-1] if has_newline else physical_line
        if line.endswith("\r"):
            line = line[:-1]
        trailing_backslashes = len(line) - len(line.rstrip("\\"))
        if has_newline and trailing_backslashes % 2 == 1:
            pending += line[:-1]
            continue
        logical_lines.append(pending + line)
        pending = ""
    if pending:
        logical_lines.append(pending)
    return any(
        user_command_pattern.search(line) and lpadmin_group_pattern.search(line)
        for line in logical_lines
    )


command_name = "user" + "mod"
positive_lpadmin_commands = [
    f"{command_name} -aG lpadmin administrator",
    f"{command_name} -aG wheel,lpadmin administrator",
    f"{command_name} -aGlpadmin administrator",
    f"{command_name} -aGwheel,lpadmin administrator",
    f"{command_name} --append --groups lpadmin administrator",
    f"{command_name} --groups=wheel,lpadmin --append administrator",
    f"{command_name} -G lpadmin -a administrator",
    f'echo "Run {command_name} -aG lpadmin administrator"',
    f"echo 'Run {command_name} --groups lpadmin --append administrator'",
    f"{command_name} -aG wheel,\\\nlpadmin administrator",
    f'{command_name} --append --groups "$groups,lpadmin" administrator',
    f'{command_name} -a -G wheel -c "note -G lpadmin" administrator',
    f"{command_name} -aG wheel administrator; {command_name} -G lpadmin other",
    f"{command_name} -d/data -Glpadmin administrator",
    f"{command_name} -aG lpadmin${{suffix}} administrator",
    (b"\xff " + command_name.encode() + b" -aG lpadmin administrator").decode(
        "utf-8", errors="surrogateescape"
    ),
]
negative_lpadmin_commands = [
    f"{command_name} -aG lpadmin-old administrator",
    f"{command_name} -aG wheel,lpadmin-old administrator",
    f"{command_name} -aG wheel administrator",
    f"printf lpadmin",
    f"{command_name}-old -aG lpadmin administrator",
    f"foo-{command_name} -aG lpadmin administrator",
    f"{command_name} x-Glpadmin administrator",
    f"{command_name} foo-aGlpadmin administrator",
    f"{command_name} -aG wheel administrator " + "\\\\" + "\nprintf lpadmin",
]
require(
    all(has_ephemeral_lpadmin_edit(command) for command in positive_lpadmin_commands),
    "ephemeral lpadmin detector misses a supported command form",
)
require(
    not any(has_ephemeral_lpadmin_edit(command) for command in negative_lpadmin_commands),
    "ephemeral print-admin detector confuses a different group or unrelated text",
)

ephemeral_lpadmin_guidance: list[str] = []
lpadmin_scan_errors: list[str] = []
for path in tracked_paths:
    try:
        data = path.read_bytes()
    except OSError:
        lpadmin_scan_errors.append(str(path.relative_to(ROOT)))
        continue
    if b"\0" in data:
        continue
    text = data.decode("utf-8", errors="surrogateescape")
    if has_ephemeral_lpadmin_edit(text):
        ephemeral_lpadmin_guidance.append(str(path.relative_to(ROOT)))

require(
    not lpadmin_scan_errors,
    "tracked text files could not be scanned: " + ", ".join(lpadmin_scan_errors),
)
require(
    not ephemeral_lpadmin_guidance,
    "tracked configuration or guidance recommends an ephemeral lpadmin group edit: "
    + ", ".join(ephemeral_lpadmin_guidance),
)
require(
    'users.groups.lpadmin.members = [ "<exact-sssd-user-name>" ];' in printserver_users,
    "print server documentation lacks a persistent SSSD print-admin workflow",
)

violations: list[str] = []
# hosts/LaptopAP is a standalone throwaway installer ISO, not a private
# device — its baked-in yescrypt hash is an explicit tradeoff (no SOPS on
# the installed system). Exempt it from the no-literal-hash policy.
EXEMPT_HASH_HOSTS = {Path("hosts/LaptopAP/installed/default.nix")}
for path in ROOT.rglob("*.nix"):
    text = path.read_text()
    if re.search(r'\binitialPassword\s*=', text):
        violations.append(f"{path.relative_to(ROOT)}: initialPassword")
    if re.search(r'\bpassword\s*=\s*"', text):
        violations.append(f"{path.relative_to(ROOT)}: plaintext password")
    if path.relative_to(ROOT) in EXEMPT_HASH_HOSTS:
        continue
    for match in re.finditer(r'\bhashedPassword\s*=\s*"([^"]*)"', text):
        if match.group(1) != "!":
            violations.append(f"{path.relative_to(ROOT)}: literal password hash")
require(not violations, "unsafe password assignments: " + ", ".join(violations))

print("private account regressions: PASS")
