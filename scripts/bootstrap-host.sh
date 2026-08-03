#!/usr/bin/env bash
# Safely provision an already-authored NixOS host from this flake.
# Secrets are prepared before first activation, installation pauses before
# reboot for an ESP/NVRAM check, and destructive work requires an exact phrase.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bootstrap-host.sh <hostname> <ip-or-dns-name>

For a host already registered in .sops.yaml, set HOST_AGE_KEY_FILE to its
existing private age key. The script refuses implicit host-key rotation.
EOF
}

host_key_sets_overlap() {
  python3 - "$1" "$2" <<'PY'
import sys


def keys(path):
    result = set()
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            fields = line.split()
            if len(fields) >= 3 and fields[-2].startswith(("ssh-", "ecdsa-", "sk-")):
                result.add((fields[-2], fields[-1]))
    return result


raise SystemExit(0 if keys(sys.argv[1]) & keys(sys.argv[2]) else 1)
PY
}

filter_host_keys_to_overlap() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys


def key_from_line(line):
    fields = line.split()
    if len(fields) >= 3 and fields[-2].startswith(("ssh-", "ecdsa-", "sk-")):
        return fields[-2], fields[-1]
    return None


with open(sys.argv[1], encoding="utf-8") as handle:
    trusted = {key for line in handle if (key := key_from_line(line)) is not None}

matched = []
with open(sys.argv[2], encoding="utf-8") as handle:
    for line in handle:
        if key_from_line(line) in trusted:
            matched.append(line)

if not matched:
    raise SystemExit(1)
with open(sys.argv[3], "w", encoding="utf-8") as handle:
    handle.writelines(matched)
PY
}

network_cidr_for_target() {
  python3 - "$1" <<'PY'
import ipaddress
import json
import subprocess
import sys
import socket


target = socket.gethostbyname(sys.argv[1])
route = json.loads(subprocess.check_output(["ip", "-j", "route", "get", target]))[0]
dev = route["dev"]
source = ipaddress.ip_address(route.get("prefsrc") or route.get("src"))
addresses = json.loads(subprocess.check_output(["ip", "-j", "address", "show", "dev", dev]))
for interface in addresses:
    for entry in interface.get("addr_info", []):
        if entry.get("family") != "inet":
            continue
        network = ipaddress.ip_network(f"{entry['local']}/{entry['prefixlen']}", strict=False)
        if source in network and ipaddress.ip_address(target) in network:
            if network.num_addresses > 4096:
                raise SystemExit("refusing to scan a network larger than /20")
            print(network)
            raise SystemExit(0)
raise SystemExit("could not determine the directly connected target network")
PY
}

neighbor_ips_in_cidr() {
  ip -j neigh | python3 -c '
import ipaddress, json, sys
network = ipaddress.ip_network(sys.argv[1], strict=True)
usable = {"REACHABLE", "STALE", "DELAY", "PROBE", "PERMANENT"}
for entry in json.load(sys.stdin):
    try:
        address = ipaddress.ip_address(entry.get("dst", ""))
    except ValueError:
        continue
    if address in network and set(entry.get("state", [])) & usable:
        print(address)
' "$1"
}

confirm_installer_host_key() {
  local known_hosts=$1
  local target=$2
  local expected=${INSTALLER_HOST_FINGERPRINT:-}
  local filtered="${known_hosts}.verified"
  local fingerprint key_type
  local matched=0

  if [[ -z "$expected" ]]; then
    echo "Read the ED25519 SHA-256 fingerprint from the target console." >&2
    printf 'Fingerprint for %s: ' "$target" >&2
    read -r expected
  fi
  [[ "$expected" == SHA256:* ]] \
    || { echo "ERROR: expected an ED25519 SHA-256 host fingerprint" >&2; return 1; }

  : >"$filtered"
  while IFS= read -r line; do
    read -r _ fingerprint _ key_type < <(
      printf '%s\n' "$line" | ssh-keygen -E sha256 -lf - 2>/dev/null
    ) || continue
    if [[ "$key_type" == '(ED25519)' && "$fingerprint" == "$expected" ]]; then
      printf '%s\n' "$line" >>"$filtered"
      matched=1
    fi
  done <"$known_hosts"
  if ((matched == 0)); then
    rm -f "$filtered"
    echo "ERROR: installer host fingerprint does not match the out-of-band value" >&2
    return 1
  fi
  mv "$filtered" "$known_hosts"
}

if [[ ${BOOTSTRAP_HOST_LIB_ONLY:-0} == 1 ]]; then
  return 0 2>/dev/null || exit 0
fi

[[ $# -eq 2 ]] || { usage >&2; exit 2; }
HOSTNAME=$1
IP=$2
[[ "$HOSTNAME" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] \
  || { echo "ERROR: invalid hostname: $HOSTNAME" >&2; exit 2; }
[[ "$IP" =~ ^[A-Za-z0-9][A-Za-z0-9.:-]*$ ]] \
  || { echo "ERROR: invalid IP/DNS target: $IP" >&2; exit 2; }

FLAKE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_REPO="${HOME}/nixos-secrets"
SOPS_YAML="${SECRETS_REPO}/.sops.yaml"
TMP_ROOT=""
RECOVERY_KEY_FILE=""
SECRETS_MUTATED=0
SECRETS_COMMITTED=0

cleanup() {
  local rc=$?
  if ((rc != 0 && SECRETS_MUTATED && !SECRETS_COMMITTED)); then
    echo "Restoring the previously clean secrets checkout..." >&2
    git -C "$SECRETS_REPO" restore --staged --worktree -- . >/dev/null 2>&1 || true
  fi
  if [[ -n "$RECOVERY_KEY_FILE" ]]; then
    if ((rc == 0 || !SECRETS_COMMITTED)); then
      rm -f -- "$RECOVERY_KEY_FILE"
    else
      echo "IMPORTANT: generated recovery key retained at $RECOVERY_KEY_FILE" >&2
    fi
  fi
  [[ -z "$TMP_ROOT" ]] || rm -rf -- "$TMP_ROOT"
  return "$rc"
}
trap cleanup EXIT

for command in age-keygen git ip just nix nmap python3 sops ssh ssh-keygen ssh-keyscan tar; do
  command -v "$command" >/dev/null \
    || { echo "ERROR: required command not found: $command" >&2; exit 1; }
done
[[ -f "$SOPS_YAML" ]] || { echo "ERROR: missing $SOPS_YAML" >&2; exit 1; }
[[ "$(git -C "$FLAKE_ROOT" status --porcelain)" == "" ]] \
  || { echo "ERROR: flake checkout is not clean; commit or stash it first" >&2; exit 1; }
[[ "$(git -C "$SECRETS_REPO" status --porcelain)" == "" ]] \
  || { echo "ERROR: secrets checkout is not clean; commit or stash it first" >&2; exit 1; }
[[ "$(git -C "$SECRETS_REPO" branch --show-current)" == main ]] \
  || { echo "ERROR: secrets checkout must be on branch main" >&2; exit 1; }

cd "$FLAKE_ROOT"
evaluated_hostname=$(nix eval --raw ".#nixosConfigurations.\"${HOSTNAME}\".config.networking.hostName")
[[ "$evaluated_hostname" == "$HOSTNAME" ]] \
  || { echo "ERROR: evaluated hostname '$evaluated_hostname' does not match '$HOSTNAME'" >&2; exit 1; }
disk_device=$(nix eval --raw ".#nixosConfigurations.\"${HOSTNAME}\".config.disko.devices.disk.main.device")
[[ "$disk_device" == /dev/disk/by-id/* && "$disk_device" != *-part* ]] \
  || { echo "ERROR: disko target must be a whole-disk /dev/disk/by-id path" >&2; exit 1; }
hashed_password_file=$(nix eval --json \
  ".#nixosConfigurations.\"${HOSTNAME}\".config.users.users.jaide.hashedPasswordFile" \
  | python3 -c 'import json, sys; print(json.load(sys.stdin) or "")')
uses_private_password_secret=0
if [[ -n "$hashed_password_file" ]]; then
  early_password_secret=$(nix eval --json \
    ".#nixosConfigurations.\"${HOSTNAME}\".config.sops.secrets.jaide_password_hash.neededForUsers")
  mutable_users=$(nix eval --json \
    ".#nixosConfigurations.\"${HOSTNAME}\".config.users.mutableUsers")
  [[ "$early_password_secret" == true ]] \
    || { echo "ERROR: jaide_password_hash must set neededForUsers = true" >&2; exit 1; }
  [[ "$mutable_users" == false ]] \
    || { echo "ERROR: SOPS password hashes require users.mutableUsers = false" >&2; exit 1; }
  [[ "$hashed_password_file" == /run/secrets-for-users/* ]] \
    || { echo "ERROR: jaide hashedPasswordFile is not an early sops-nix secret" >&2; exit 1; }
  uses_private_password_secret=1
fi
[[ "$(nix eval --json ".#nixosConfigurations.\"${HOSTNAME}\".config.services.openssh.enable")" == true ]] \
  || { echo "ERROR: target configuration must enable OpenSSH" >&2; exit 1; }
authorized_key_count=$(nix eval --json ".#nixosConfigurations.\"${HOSTNAME}\".config.users.users.jaide.openssh.authorizedKeys.keys" --apply builtins.length)
((authorized_key_count > 0)) || { echo "ERROR: jaide has no authorized SSH key" >&2; exit 1; }
nix eval --raw ".#nixosConfigurations.\"${HOSTNAME}\".config.system.build.toplevel.drvPath" >/dev/null
nix fmt -- --check . >/dev/null

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-${HOSTNAME}.XXXXXX")
KNOWN_HOSTS="${TMP_ROOT}/known_hosts"
HOST_KEY_FILE="${TMP_ROOT}/host-age-key.txt"
SOPS_BEFORE="${TMP_ROOT}/sops-before.yaml"
SOPS_VERIFY_CONFIG="${TMP_ROOT}/xdg-verify"
REMOTE_FLAKE="/tmp/nixos-bootstrap-flake"
REMOTE_SECRETS="/tmp/nixos-bootstrap-secrets"
mkdir -m 0700 "$SOPS_VERIFY_CONFIG"

if [[ -n ${INSTALLER_KNOWN_HOSTS_FILE:-} ]]; then
  [[ -f "$INSTALLER_KNOWN_HOSTS_FILE" ]] \
    || { echo "ERROR: pre-provisioned known-hosts file is missing: $INSTALLER_KNOWN_HOSTS_FILE" >&2; exit 1; }
  install -m 0600 "$INSTALLER_KNOWN_HOSTS_FILE" "$KNOWN_HOSTS"
  ssh-keygen -F "$IP" -f "$KNOWN_HOSTS" >/dev/null \
    || { echo "ERROR: pre-provisioned known-hosts file has no entry for $IP" >&2; exit 1; }
else
  ssh-keyscan -T 5 "$IP" >"$KNOWN_HOSTS" 2>/dev/null
  [[ -s "$KNOWN_HOSTS" ]] || { echo "ERROR: cannot obtain installer SSH host key from $IP" >&2; exit 1; }
  echo "Installer SSH host-key fingerprints:"
  ssh-keygen -E sha256 -lf "$KNOWN_HOSTS"
  confirm_installer_host_key "$KNOWN_HOSTS" "$IP"
fi
SSH_PREFLIGHT=(
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o "UserKnownHostsFile=${KNOWN_HOSTS}"
  -o StrictHostKeyChecking=yes
)
if ! ssh "${SSH_PREFLIGHT[@]}" "root@${IP}" true 2>/dev/null; then
  if [[ -n "${SSHPASS:-}" ]]; then
    command -v sshpass >/dev/null || { echo "ERROR: SSHPASS is set but sshpass is unavailable" >&2; exit 1; }
    sshpass -e ssh-copy-id -o "UserKnownHostsFile=${KNOWN_HOSTS}" -o StrictHostKeyChecking=yes \
      -i "${HOME}/.ssh/id_ed25519.pub" "root@${IP}" >/dev/null
  fi
fi
ssh "${SSH_PREFLIGHT[@]}" "root@${IP}" true \
  || { echo "ERROR: root SSH to the installer failed" >&2; exit 1; }
ssh "${SSH_PREFLIGHT[@]}" "root@${IP}" \
  'set -euo pipefail; command -v python3 >/dev/null; test -d /sys/firmware/efi/efivars; test -w /sys/firmware/efi/efivars; efibootmgr -v >/dev/null' \
  || { echo "ERROR: installer must provide python3 and writable UEFI variables" >&2; exit 1; }

remote_inventory=$(ssh "${SSH_PREFLIGHT[@]}" "root@${IP}" bash -s -- "$disk_device" <<'REMOTE'
set -euo pipefail
disk=$1
[[ -e "$disk" ]] || { echo "ERROR: configured target disk is absent: $disk" >&2; exit 1; }
real_disk=$(readlink -f "$disk")
[[ -b "$real_disk" ]] || { echo "ERROR: not a block device: $disk -> $real_disk" >&2; exit 1; }
echo "Configured target: $disk -> $real_disk"
lsblk -d -o NAME,PATH,SIZE,MODEL,SERIAL,TRAN "$real_disk"
lsblk -f "$real_disk"
if lsblk -nr -o MOUNTPOINTS "$real_disk" | grep -q '[^[:space:]]'; then
  echo "WARNING: the target disk or a partition appears mounted."
fi
REMOTE
)
printf '%s\n' "$remote_inventory"
target_cidr=$(network_cidr_for_target "$IP")
echo "Post-boot discovery will authenticate SSH candidates within $target_cidr"

confirmation_phrase="WIPE ${disk_device} ON ${IP}"
echo "Verify the model/serial and backups, then type exactly:"
printf '  %s\n> ' "$confirmation_phrase"
read -r confirmation
[[ "$confirmation" == "$confirmation_phrase" ]] || { echo "Aborted." >&2; exit 1; }

registered_pubkey=$(grep -oP "^[[:space:]]*-[[:space:]]*&host_${HOSTNAME}[[:space:]]+\Kage1[a-z0-9]+" "$SOPS_YAML" || true)
if [[ -n "$registered_pubkey" ]]; then
  [[ -n "${HOST_AGE_KEY_FILE:-}" && -f "${HOST_AGE_KEY_FILE}" ]] || {
    echo "ERROR: host_${HOSTNAME} is already registered; set HOST_AGE_KEY_FILE to its existing private key" >&2
    exit 1
  }
  install -m 0600 "$HOST_AGE_KEY_FILE" "$HOST_KEY_FILE"
  host_pubkey=$(age-keygen -y "$HOST_KEY_FILE")
  [[ "$host_pubkey" == "$registered_pubkey" ]] \
    || { echo "ERROR: HOST_AGE_KEY_FILE does not match the registered recipient" >&2; exit 1; }
else
  age-keygen -o "$HOST_KEY_FILE" >/dev/null
  chmod 0600 "$HOST_KEY_FILE"
  host_pubkey=$(age-keygen -y "$HOST_KEY_FILE")
  recovery_dir="${HOME}/.local/state/nixos-bootstrap"
  install -d -m 0700 "$recovery_dir"
  RECOVERY_KEY_FILE="${recovery_dir}/${HOSTNAME}-age.key"
  install -m 0600 "$HOST_KEY_FILE" "$RECOVERY_KEY_FILE"
fi

cp -- "$SOPS_YAML" "$SOPS_BEFORE"
python3 "${FLAKE_ROOT}/scripts/register-sops-host.py" "$SOPS_YAML" "$HOSTNAME" "$host_pubkey"
if ! cmp -s "$SOPS_BEFORE" "$SOPS_YAML"; then
  SECRETS_MUTATED=1
fi

relevant_secret_files=()
while IFS= read -r -d '' file; do
  case "$file" in
    secrets.yaml|secrets/shared/*.yaml|"secrets/${HOSTNAME}/"*.yaml)
      relevant_secret_files+=("$file")
      ;;
    secrets/private/*.yaml)
      ((uses_private_password_secret)) && relevant_secret_files+=("$file")
      ;;
  esac
done < <(git -C "$SECRETS_REPO" ls-files -z '*.yaml')
((${#relevant_secret_files[@]} > 0)) \
  || { echo "ERROR: no encrypted secret files apply to $HOSTNAME" >&2; exit 1; }

if ((SECRETS_MUTATED)); then
  if [[ -n "${SOPS_AGE_KEY_FILE:-}" && -f "${SOPS_AGE_KEY_FILE}" ]]; then
    :
  elif sudo -n true 2>/dev/null; then
    local_admin_key="${TMP_ROOT}/local-admin-age-key.txt"
    sudo install -m 0600 -o "$(id -u)" -g "$(id -g)" /var/lib/sops-nix/key.txt "$local_admin_key"
    SOPS_AGE_KEY_FILE="$local_admin_key"
    export SOPS_AGE_KEY_FILE
  else
    echo "ERROR: recipient update needs SOPS_AGE_KEY_FILE or cached sudo credentials" >&2
    exit 1
  fi
  for file in "${relevant_secret_files[@]}"; do
    echo "Updating recipients: $file"
    (cd "$SECRETS_REPO" && sops updatekeys --yes "$file")
  done
fi
for file in "${relevant_secret_files[@]}"; do
  echo "Verifying new host key: $file"
  XDG_CONFIG_HOME="${SOPS_VERIFY_CONFIG}" SOPS_AGE_KEY_FILE="${HOST_KEY_FILE}" \
    sops --decrypt "${SECRETS_REPO}/${file}" >/dev/null
done

runtime_dir="/run/user/$(id -u)"
if [[ -S "${runtime_dir}/gcr/ssh" ]]; then
  SSH_AUTH_SOCK="${runtime_dir}/gcr/ssh"
  export SSH_AUTH_SOCK
fi
if ((SECRETS_MUTATED)); then
  git -C "$SECRETS_REPO" diff --check
  git -C "$SECRETS_REPO" add -- .sops.yaml "${relevant_secret_files[@]}"
  git -C "$SECRETS_REPO" commit -m "Add ${HOSTNAME} host age key to sops"
  SECRETS_COMMITTED=1
fi
# This is intentionally unconditional: it recovers cleanly from a previous
# run whose local commit succeeded but whose push or lock update failed.
git -C "$SECRETS_REPO" push origin main
cd "$FLAKE_ROOT"
nix flake update nixos-secrets
nix eval --raw ".#nixosConfigurations.\"${HOSTNAME}\".config.system.build.toplevel.drvPath" >/dev/null

ssh "${SSH_PREFLIGHT[@]}" "root@${IP}" \
  systemctl mask --runtime sleep.target suspend.target hibernate.target hybrid-sleep.target

# nixos-anywhere 1.13.0 initializes unchecked SSH options before user-supplied
# options. OpenSSH uses the first value, so appending strict options would not
# override them. Run a temporary copy with only its generated identity option;
# every host-key policy then comes from the pinned installer known_hosts file.
NA_OUT=$(nix build --no-link --print-out-paths "${FLAKE_ROOT}#nixos-anywhere")
NA_TRUST_DIR="${TMP_ROOT}/nixos-anywhere-libexec"
cp -a "${NA_OUT}/libexec/nixos-anywhere" "$NA_TRUST_DIR"
chmod -R u+w "$NA_TRUST_DIR"
NA_SOURCE="${NA_TRUST_DIR}/nixos-anywhere.sh"
TRUSTED_NA="$NA_SOURCE"
python3 - "$NA_SOURCE" "$TRUSTED_NA" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
unsafe = (
    'declare -a sshArgs=("-o" "IdentitiesOnly=yes" "-i" "$tempDir/nixos-anywhere" '
    '"-o" "UserKnownHostsFile=' + '/dev/null" "-o" "StrictHostKeyChecking=' + 'no")'
)
safe = 'declare -a sshArgs=("-o" "IdentitiesOnly=yes" "-i" "$tempDir/nixos-anywhere")'
if source.count(unsafe) != 1:
    raise SystemExit("refusing unknown nixos-anywhere SSH initialization")
Path(sys.argv[2]).write_text(source.replace(unsafe, safe))
PY
chmod 0700 "$TRUSTED_NA"
NA_SSH_OPTIONS=(
  --ssh-option "UserKnownHostsFile=${KNOWN_HOSTS}"
  --ssh-option StrictHostKeyChecking=yes
)
"$TRUSTED_NA" \
  --flake "${FLAKE_ROOT}#${HOSTNAME}" \
  --target-host "root@${IP}" \
  --phases kexec,disko \
  "${NA_SSH_OPTIONS[@]}"

# nixos-anywhere establishes the trusted installer and applies Disko. The
# actual OS installation is deliberately target-side `nixos-install --flake`.
# Transfer only Git-tracked source files; the secrets checkout contains SOPS
# ciphertext, never decrypted values.
ssh "${SSH_PREFLIGHT[@]}" "root@${IP}" \
  "rm -rf '${REMOTE_FLAKE}' '${REMOTE_SECRETS}'; mkdir -p '${REMOTE_FLAKE}' '${REMOTE_SECRETS}'"
git -C "$FLAKE_ROOT" ls-files -z \
  | tar -C "$FLAKE_ROOT" --null --files-from=- -czf - \
  | ssh "${SSH_PREFLIGHT[@]}" "root@${IP}" "tar -xzf - -C '${REMOTE_FLAKE}'"
git -C "$SECRETS_REPO" ls-files -z \
  | tar -C "$SECRETS_REPO" --null --files-from=- -czf - \
  | ssh "${SSH_PREFLIGHT[@]}" "root@${IP}" "tar -xzf - -C '${REMOTE_SECRETS}'"

# Install both identities before first activation: the age key unlocks SOPS,
# while copying the already-authenticated installer host keys preserves SSH
# host identity across the reboot.
ssh "${SSH_PREFLIGHT[@]}" "root@${IP}" \
  'set -e; install -d -m 0700 /mnt/var/lib/sops-nix; umask 077; cat > /mnt/var/lib/sops-nix/key.txt; chmod 0600 /mnt/var/lib/sops-nix/key.txt; install -d -m 0755 /mnt/etc/ssh; cp -a /etc/ssh/ssh_host_* /mnt/etc/ssh/' \
  <"$HOST_KEY_FILE"

ssh "${SSH_PREFLIGHT[@]}" "root@${IP}" bash -s -- \
  "$REMOTE_FLAKE" "$REMOTE_SECRETS" "$HOSTNAME" <<'REMOTE'
set -euo pipefail
remote_flake=$1
remote_secrets=$2
host=$3
nix --extra-experimental-features 'nix-command flakes' flake lock \
  --override-input nixos-secrets "path:${remote_secrets}" \
  "$remote_flake"
PATH="/nix/var/nix/profiles/system/sw/bin:${PATH}" \
  /run/current-system/sw/bin/nixos-install \
    --flake "path:${remote_flake}#${host}" \
    --no-root-password \
    --option experimental-features 'nix-command flakes'
REMOTE

ssh "${SSH_PREFLIGHT[@]}" "root@${IP}" bash -s -- "$disk_device" \
  <"${FLAKE_ROOT}/scripts/verify-installed-boot.sh"

"$TRUSTED_NA" \
  --flake "${FLAKE_ROOT}#${HOSTNAME}" \
  --target-host "root@${IP}" \
  --phases reboot \
  "${NA_SSH_OPTIONS[@]}"

echo "Waiting up to 300 seconds for the installed system..."
installed_up=0
candidate_keys="$TMP_ROOT/postboot-known-hosts"
candidate_scan="$TMP_ROOT/postboot-scanned-hosts"
for _ in $(seq 1 60); do
  nmap -sn "$target_cidr" >/dev/null 2>&1 || true
  candidates=("$IP")
  while IFS= read -r discovered_ip; do
    [[ -n "$discovered_ip" && "$discovered_ip" != "$IP" ]] \
      && candidates+=("$discovered_ip")
  done < <(neighbor_ips_in_cidr "$target_cidr")

  for candidate_ip in "${candidates[@]}"; do
    : >"$candidate_scan"
    ssh-keyscan -T 2 "$candidate_ip" >"$candidate_scan" 2>/dev/null || continue
    filter_host_keys_to_overlap "$KNOWN_HOSTS" "$candidate_scan" "$candidate_keys" || continue
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -o "UserKnownHostsFile=${candidate_keys}" -o StrictHostKeyChecking=yes \
      "jaide@${candidate_ip}" 'printf installed' 2>/dev/null | grep -q '^installed$'; then
      cat "$candidate_keys" >>"$KNOWN_HOSTS"
      IP=$candidate_ip
      installed_up=1
      break 2
    fi
  done
  sleep 5
done
((installed_up)) \
  || { echo "ERROR: installed host did not return on an authenticated SSH key within $target_cidr" >&2; exit 1; }
echo "Authenticated installed host at post-boot address $IP"

remote_status=$(ssh -o BatchMode=yes -o "UserKnownHostsFile=${KNOWN_HOSTS}" -o StrictHostKeyChecking=yes \
  "jaide@${IP}" 'printf "hostname=%s\n" "$(hostname)"; systemctl is-system-running --wait; test -f /run/secrets/ssh_key; printf "password_state=%s\n" "$(passwd -S jaide | cut -d " " -f 2)"')
printf '%s\n' "$remote_status"
[[ "$remote_status" == *"hostname=${HOSTNAME}"* && "$remote_status" == *running* && "$remote_status" == *"password_state=P"* ]] \
  || { echo "ERROR: installed hostname/system state/password verification failed" >&2; exit 1; }

echo "${HOSTNAME} is installed: SSH works, sops created ssh_key, system state is running, and bootability was proven before reboot."
if git -C "$FLAKE_ROOT" diff --quiet -- flake.lock; then
  :
else
  echo "Review and commit the flake.lock update: git -C $FLAKE_ROOT diff -- flake.lock"
fi
echo "The SOPS-managed password hash is active; verify sudo with: ssh -t jaide@${IP} sudo -v"
