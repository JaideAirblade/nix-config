#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
script=scripts/bootstrap-host.sh
justfile=Justfile

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require() {
  local needle=$1
  local label=$2
  grep -Fq -- "$needle" "$script" || fail "$label"
}

reject() {
  local needle=$1
  local label=$2
  if grep -Fq -- "$needle" "$script"; then
    fail "$label"
  fi
}

require 'read -r confirmation' "provisioning lacks an explicit typed wipe confirmation"
require 'WIPE ${disk_device} ON ${IP}' "confirmation is not bound to the exact disk and target"
require 'SOPS_AGE_KEY_FILE="${HOST_KEY_FILE}"' "new host key is not selected for verification"
require 'sops --decrypt "${SECRETS_REPO}/${file}" >/dev/null' "new host key is not tested before installation"
require 'XDG_CONFIG_HOME="${SOPS_VERIFY_CONFIG}"' "host-key verification can fall back to interactive user identities"
require '--phases kexec,disko' "nixos-anywhere does not perform the remote bootstrap and Disko phases"
require 'CONTROLLER_TOPLEVEL=$(nix build --out-link "${TMP_ROOT}/controller-toplevel" --print-out-paths' "controller closure is not GC-rooted through destructive phases"
require 'nix copy --to "ssh-ng://root@${IP}" "$CONTROLLER_TOPLEVEL"' "controller closure is not copied over authenticated SSH"
require 'NIX_SSHOPTS="-F ${NIX_SSH_CONFIG}"' "nix copy does not use a whitespace-safe SSH config"
require 'TMP_ROOT=$(mktemp -d "/tmp/bootstrap-${HOSTNAME}.XXXXXX")' "security-sensitive temporary paths are not constrained beneath /tmp"
require '/run/current-system/sw/bin/nixos-install' "target installation is not performed by nixos-install"
require '--flake "path:${remote_flake}#${host}"' "nixos-install does not consume the transferred flake"
require 'config.users.users.jaide.hashedPasswordFile' "bootstrap does not verify hashedPasswordFile wiring"
require 'cat > /mnt/var/lib/sops-nix/key.txt' "prepared SOPS host key is not installed before first activation"
require 'cp -a /etc/ssh/ssh_host_' "authenticated installer host keys are not preserved"
require 'git -C "$FLAKE_ROOT" ls-files -z' "flake transfer is not limited to reviewed tracked files"
require 'command -v python3 >/dev/null; test -d /sys/firmware/efi/efivars' "target-side Python is not checked before destructive provisioning"
require 'test -w /sys/firmware/efi/efivars' "writable UEFI variables are not checked before destructive provisioning"
require 'efibootmgr -v' "EFI NVRAM readability is not checked"
require 'verify-installed-boot.sh' "tested installed-boot verifier is not invoked"
require 'config.sops.secrets.jaide_password_hash.neededForUsers' "bootstrap does not verify the early password secret"
require 'config.users.users.jaide.hashedPasswordFile' "bootstrap does not verify hashedPasswordFile wiring"
require 'config.users.mutableUsers' "bootstrap does not verify declarative password enforcement"
require 'secrets/private/*.yaml' "private-device password secrets are omitted from host-key verification"
require 'passwd -S jaide' "post-boot verification does not prove Jaide has an active hash"
require 'neighbor_ips_in_cidr' "bootstrap does not enumerate post-boot addresses independently of MAC"
require 'nmap -sn' "bootstrap cannot rediscover a host whose DHCP address changes"
require 'ip -j neigh' "bootstrap does not enumerate reachable candidates after the CIDR scan"
require 'filter_host_keys_to_overlap' "rediscovered addresses are not reduced to the pinned host identity"
require 'IP=$candidate_ip' "bootstrap does not adopt the authenticated post-boot DHCP address"
require '--phases reboot' "verified installation is not cleanly rebooted through nixos-anywhere"
require 'trap cleanup EXIT' "temporary private key cleanup is missing"
require 'systemctl mask --runtime sleep.target suspend.target hibernate.target hybrid-sleep.target' "installer suspend is not masked"

require 'cp -a "${NA_OUT}/libexec/nixos-anywhere" "$NA_TRUST_DIR"' "trusted nixos-anywhere copy omits required support scripts"
require 'chmod -R u+w "$NA_TRUST_DIR"' "trusted nixos-anywhere copy remains immutable"
require 'StrictHostKeyChecking=yes' "provisioning does not enforce authenticated SSH host keys"

reject 'StrictHostKeyChecking=no' "provisioning disables SSH host authentication before transmitting secrets"
reject 'UserKnownHostsFile=/dev/null' "provisioning discards its pinned SSH host keys"
reject '--generate-hardware-config' "provisioning can overwrite the reviewed hardware module and conflict with disko"
reject '--phases kexec,disko,install' "nixos-anywhere still performs the final install phase"
reject 'CONTROLLER_TOPLEVEL=$(nix build --no-link' "controller closure can be garbage-collected after disk wipe"
reject 'scp ${SSH_OPTS} "jaide@${IP}:/var/lib/sops-nix/key.txt"' "bootstrap still tries to read the root-owned key as jaide"
reject 'nixos-enter --root /mnt' "bootstrap still uses an imperative password mutation"
reject 'passwd jaide' "bootstrap still prompts for a password outside SOPS"
reject 'sops updatekeys --yes "${f}" ||' "secret re-encryption failures are ignored"
reject 'git push origin main 2>&1 ||' "secrets push failures are ignored"
reject 'esp="${disk}-part1"' "generic provisioner still hard-codes ESP partition 1"

python3 - "$script" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
uefi = text.find('test -w /sys/firmware/efi/efivars')
wipe = text.find('confirmation_phrase="WIPE ${disk_device} ON ${IP}"')
if uefi < 0 or wipe < 0 or uefi > wipe:
    raise SystemExit('FAIL: UEFI capability is not proven before wipe confirmation')

disko = text.find('--phases kexec,disko')
copy = text.find('nix copy --to "ssh-ng://root@${IP}" "$CONTROLLER_TOPLEVEL"')
install = text.find('/run/current-system/sw/bin/nixos-install')
if min(disko, copy, install) < 0 or not disko < copy < install:
    raise SystemExit('FAIL: controller closure copy must occur after Disko and before nixos-install')

ssh_config = text.find('NIX_SSH_CONFIG="${TMP_ROOT}/nix-ssh-config"')
if ssh_config < 0 or ssh_config > copy:
    raise SystemExit('FAIL: whitespace-safe Nix SSH config is not created before closure copy')
PY

if grep -Fq -- '--generate-hardware-config' "$justfile"; then
  fail "Justfile can still overwrite the reviewed hardware module during provisioning"
fi
provision_body=$(just --dump --dump-format json | python3 -c 'import json,sys; print(json.load(sys.stdin)["recipes"]["provision"]["body"][0])')
[[ "$provision_body" == *'bootstrap-host.sh'* ]] \
  || fail "just provision bypasses the safe bootstrap workflow"
if just --dry-run provision 'UwU; printf INJECTED' '127.0.0.1' >/dev/null 2>&1; then
  fail "just provision accepts a shell-metacharacter hostname"
fi
if just --dry-run provision 'UwU-Server' '127.0.0.1; printf INJECTED' >/dev/null 2>&1; then
  fail "just provision accepts a shell-metacharacter target"
fi

printf 'bootstrap-host regressions: PASS\n'
