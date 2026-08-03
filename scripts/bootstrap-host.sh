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

for command in age-keygen git just nix python3 sops ssh ssh-keygen ssh-keyscan; do
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
[[ "$(nix eval --json ".#nixosConfigurations.\"${HOSTNAME}\".config.services.openssh.enable")" == true ]] \
  || { echo "ERROR: target configuration must enable OpenSSH" >&2; exit 1; }
authorized_key_count=$(nix eval --json ".#nixosConfigurations.\"${HOSTNAME}\".config.users.users.jaide.openssh.authorizedKeys.keys" --apply builtins.length)
((authorized_key_count > 0)) || { echo "ERROR: jaide has no authorized SSH key" >&2; exit 1; }
nix eval --raw ".#nixosConfigurations.\"${HOSTNAME}\".config.system.build.toplevel.drvPath" >/dev/null
nix fmt -- --check . >/dev/null

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-${HOSTNAME}.XXXXXX")
KNOWN_HOSTS="${TMP_ROOT}/known_hosts"
HOST_KEY_FILE="${TMP_ROOT}/host-age-key.txt"
EXTRA_FILES="${TMP_ROOT}/extra-files"
SOPS_BEFORE="${TMP_ROOT}/sops-before.yaml"
SOPS_VERIFY_CONFIG="${TMP_ROOT}/xdg-verify"
mkdir -m 0700 "$SOPS_VERIFY_CONFIG"

ssh-keyscan -T 5 "$IP" >"$KNOWN_HOSTS" 2>/dev/null
[[ -s "$KNOWN_HOSTS" ]] || { echo "ERROR: cannot obtain installer SSH host key from $IP" >&2; exit 1; }
echo "Installer SSH host-key fingerprints (compare with the target you trust):"
ssh-keygen -lf "$KNOWN_HOSTS"
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
nix flake lock --update-input nixos-secrets
nix eval --raw ".#nixosConfigurations.\"${HOSTNAME}\".config.system.build.toplevel.drvPath" >/dev/null
install -D -m 0600 "$HOST_KEY_FILE" "${EXTRA_FILES}/var/lib/sops-nix/key.txt"

ssh "${SSH_PREFLIGHT[@]}" "root@${IP}" \
  systemctl mask --runtime sleep.target suspend.target hibernate.target hybrid-sleep.target

# nixos-anywhere 1.13.0 initializes unchecked SSH options before user-supplied
# options. OpenSSH uses the first value, so appending strict options would not
# override them. Run a temporary copy with only its generated identity option;
# every host-key policy then comes from the pinned installer known_hosts file.
NA_OUT=$(nix build --no-link --print-out-paths "${FLAKE_ROOT}#nixos-anywhere")
NA_TRUST_DIR="${TMP_ROOT}/nixos-anywhere-libexec"
cp -a "${NA_OUT}/libexec/nixos-anywhere" "$NA_TRUST_DIR"
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
  --extra-files "${EXTRA_FILES}" \
  --copy-host-keys \
  --phases kexec,disko,install \
  "${NA_SSH_OPTIONS[@]}"

verify_boot_path() {
  ssh "${SSH_PREFLIGHT[@]}" \
    "root@${IP}" bash -s -- "$disk_device" <<'REMOTE'
set -euo pipefail
disk=$1
esp="${disk}-part1"
real_disk=$(readlink -f "$disk")
[[ -b "$real_disk" && -b "$(readlink -f "$esp")" ]] || { echo "ERROR: target disk/ESP missing" >&2; exit 1; }
partuuid=$(blkid -s PARTUUID -o value "$esp")
[[ -n "$partuuid" ]] || { echo "ERROR: ESP has no PARTUUID" >&2; exit 1; }
[[ -f /mnt/boot/EFI/systemd/systemd-bootx64.efi ]] || { echo "ERROR: systemd-boot EFI binary missing" >&2; exit 1; }
compgen -G '/mnt/boot/loader/entries/*.conf' >/dev/null || { echo "ERROR: no loader entries" >&2; exit 1; }
[[ -s /mnt/boot/loader/loader.conf ]] || { echo "ERROR: loader.conf missing/empty" >&2; exit 1; }
efi_output=$(efibootmgr -v)
entry=$(grep -Fi "$partuuid" <<<"$efi_output" | grep -Fi '\EFI\systemd\systemd-bootx64.efi' | grep -oP '^Boot\K[0-9A-Fa-f]{4}' | head -1)
if [[ -z "$entry" ]]; then
  echo "Creating an EFI entry for ESP PARTUUID $partuuid"
  efibootmgr -c -d "$real_disk" -p 1 -L "Linux Boot Manager" -l '\EFI\systemd\systemd-bootx64.efi' >/dev/null
  efi_output=$(efibootmgr -v)
  entry=$(grep -Fi "$partuuid" <<<"$efi_output" | grep -Fi '\EFI\systemd\systemd-bootx64.efi' | grep -oP '^Boot\K[0-9A-Fa-f]{4}' | head -1)
fi
[[ -n "$entry" ]] || { echo "ERROR: no NVRAM entry points at the real ESP and systemd-boot executable" >&2; exit 1; }
boot_order=$(grep -oP '^BootOrder: \K.*' <<<"$efi_output" | head -1)
new_order=$entry
IFS=, read -ra old_entries <<<"$boot_order"
for old in "${old_entries[@]}"; do
  [[ "${old^^}" == "${entry^^}" || -z "$old" ]] || new_order+=",$old"
done
efibootmgr -o "$new_order" >/dev/null
echo "Verified systemd-boot, loader entries, ESP $esp ($partuuid), and BootOrder entry $entry."
REMOTE
}
verify_boot_path

echo "Set jaide's initial password inside the installed system before reboot."
echo "The password is entered directly into passwd over the verified installer SSH session; it is never stored in Git or the Nix store."
ssh -tt -o ConnectTimeout=8 -o "UserKnownHostsFile=${KNOWN_HOSTS}" -o StrictHostKeyChecking=yes \
  "root@${IP}" "nixos-enter --root /mnt --command 'passwd jaide'"

"$TRUSTED_NA" \
  --flake "${FLAKE_ROOT}#${HOSTNAME}" \
  --target-host "root@${IP}" \
  --phases reboot \
  "${NA_SSH_OPTIONS[@]}"

echo "Waiting up to 300 seconds for the installed system..."
installed_up=0
for _ in $(seq 1 60); do
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -o "UserKnownHostsFile=${KNOWN_HOSTS}" -o StrictHostKeyChecking=yes \
    "jaide@${IP}" 'printf installed' 2>/dev/null | grep -q '^installed$'; then
    installed_up=1
    break
  fi
  sleep 5
done
((installed_up)) || { echo "ERROR: installed host did not return on jaide SSH" >&2; exit 1; }

remote_status=$(ssh -o BatchMode=yes -o "UserKnownHostsFile=${KNOWN_HOSTS}" -o StrictHostKeyChecking=yes \
  "jaide@${IP}" 'printf "hostname=%s\n" "$(hostname)"; systemctl is-system-running --wait; test -f /run/secrets/ssh_key')
printf '%s\n' "$remote_status"
[[ "$remote_status" == *"hostname=${HOSTNAME}"* && "$remote_status" == *running* ]] \
  || { echo "ERROR: installed hostname/system state verification failed" >&2; exit 1; }

echo "${HOSTNAME} is installed: SSH works, sops created ssh_key, system state is running, and bootability was proven before reboot."
if git -C "$FLAKE_ROOT" diff --quiet -- flake.lock; then
  :
else
  echo "Review and commit the flake.lock update: git -C $FLAKE_ROOT diff -- flake.lock"
fi
echo "The password entered before reboot is active; verify sudo with: ssh -t jaide@${IP} sudo -v"
