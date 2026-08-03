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
require '--extra-files "${EXTRA_FILES}"' "the prepared sops host key is not installed before first activation"
require '--phases kexec,disko,install' "install does not pause before reboot for boot-path verification"
require 'verify_boot_path' "ESP/NVRAM boot-path verification is missing"
require 'efibootmgr' "EFI NVRAM verification is missing"
require 'nixos-enter --root /mnt' "installed-system password is not set before reboot"
require 'passwd jaide' "bootstrap does not establish the account password securely"
require '--phases reboot' "verified installation is not cleanly rebooted through nixos-anywhere"
require 'trap cleanup EXIT' "temporary private key cleanup is missing"
require 'systemctl mask --runtime sleep.target suspend.target hibernate.target hybrid-sleep.target' "installer suspend is not masked"
require '--copy-host-keys' "installed system does not preserve the authenticated installer host key"
require 'cp -a "${NA_OUT}/libexec/nixos-anywhere" "$NA_TRUST_DIR"' "trusted nixos-anywhere copy omits required support scripts"
require 'StrictHostKeyChecking=yes' "provisioning does not enforce authenticated SSH host keys"

reject 'StrictHostKeyChecking=no' "provisioning disables SSH host authentication before transmitting secrets"
reject 'UserKnownHostsFile=/dev/null' "provisioning discards its pinned SSH host keys"
reject '--generate-hardware-config' "provisioning can overwrite the reviewed hardware module and conflict with disko"
reject 'scp ${SSH_OPTS} "jaide@${IP}:/var/lib/sops-nix/key.txt"' "bootstrap still tries to read the root-owned key as jaide"
reject 'sops updatekeys --yes "${f}" ||' "secret re-encryption failures are ignored"
reject 'git push origin main 2>&1 ||' "secrets push failures are ignored"

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

partuuid='3976-4F53-EXAMPLE'
# Referenced by the production assignment evaluated below.
# shellcheck disable=SC2034
efi_output="Boot0007* Windows Boot Manager HD(1,GPT,${partuuid},0x800,0x100000)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)
Boot0008* Linux Boot Manager HD(1,GPT,${partuuid},0x800,0x100000)/File(\\EFI\\systemd\\systemd-bootx64.efi)"
entry=''
entry_assignment=$(grep -F 'entry=$(' "$script")
[[ -n "$entry_assignment" ]] || fail "EFI entry-selection expression is missing"
eval "$entry_assignment"
[[ "$entry" == 0008 ]] \
  || fail "EFI verification selected another loader on the same ESP instead of systemd-boot"

printf 'bootstrap-host regressions: PASS\n'
