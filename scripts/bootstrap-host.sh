#!/usr/bin/env bash
# bootstrap-host.sh — full initial provisioning of a NixOS host from this flake.
#
# v2 (2026-08-03) — reviewed after the UwU-Server install failure. Fixes:
#   1. SECRETS-FIRST, not secrets-after. If sops.secrets.* are declared in a
#      role the host gets at birth (our `common` role does), first-boot
#      activation fails at setupSecrets when the host key isn't a recipient
#      yet — and the aborted activation also skips authorized_keys.d and
#      initialPassword → the box is reachable but fully locked out.
#      The key is now generated + registered + re-encrypted BEFORE the
#      install, and the private key is staged via nixos-anywhere
#      --extra-files so first activation just works.
#   2. BOOT VERIFICATION before reboot. The last install wrote no valid EFI
#      NVRAM entry (stale "Linux Boot Manager" from the machine's previous
#      life pointed at a dead partition) — the box fell through to the USB or
#      BIOS. The script now runs nixos-anywhere with --phases
#      kexec,disko,install (no reboot), verifies the ESP + NVRAM entry
#      against the real partition UUID, fixes it if needed, and only then
#      reboots.
#   3. Live-ISO auto-suspend masked before the long closure copy (it killed
#      our first copy mid-flight).
#   4. --use-remote-sudo deploys need jaide in nix.settings.trusted-users on
#      the target, otherwise the daemon rejects the unsigned local build.
#      The script now asserts this up front instead of failing at the end.
#   5. hardware-configuration.nix is only generated if MISSING. Regenerating
#      would drop host-specific initrd force-loads (e.g. the nvme
#      boot.initrd.kernelModules fix lives in disk-layout.nix precisely so
#      regeneration can't clobber it — keep it that way).
#
# Usage:
#   just bootstrap <hostname> <ip>
#   scripts/bootstrap-host.sh <hostname> <ip>
#
# Prerequisites:
#   - Target booted from a NixOS installer USB, root SSH reachable (password
#     via SSHPASS env var, or a key already installed).
#   - The host exists in the flake with a disko disk-layout.nix.
#   - ~/nixos-secrets cloned. For re-encryption: SOPS_AGE_KEY_FILE pointing
#     at YubiKey identities, OR sudo on this machine (falls back to this
#     host's own sops key at /var/lib/sops-nix/key.txt).
set -euo pipefail

# ── Args ────────────────────────────────────────────────────────────
HOSTNAME="${1:?usage: bootstrap-host.sh <hostname> <ip>}"
IP="${2:?usage: bootstrap-host.sh <hostname> <ip>}"

FLAKE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_REPO="${HOME}/nixos-secrets"
SOPS_YAML="${SECRETS_REPO}/.sops.yaml"
AGE_KEY_FILE="/tmp/${HOSTNAME}-age.key"
EXTRA_FILES="/tmp/${HOSTNAME}-extra-files"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o ServerAliveInterval=10"

echo "════════════════════════════════════════════════════════════════"
echo "  Bootstrap: ${HOSTNAME} @ ${IP}"
echo "  Flake:     ${FLAKE_ROOT}"
echo "  Secrets:   ${SECRETS_REPO}"
echo "════════════════════════════════════════════════════════════════"

# ── Sanity checks ───────────────────────────────────────────────────
[ -f "${SOPS_YAML}" ] || { echo "ERROR: ${SOPS_YAML} not found — clone nixos-secrets first"; exit 1; }

nix eval --json ".#nixosConfigurations.${HOSTNAME}.config.networking.hostName" >/dev/null 2>&1 \
  || { echo "ERROR: ${HOSTNAME} not found in flake nixosConfigurations"; exit 1; }

disk_device=$(nix eval --raw ".#nixosConfigurations.${HOSTNAME}.config.disko.devices.disk.main.device" 2>/dev/null || echo "")
[ -n "${disk_device}" ] || { echo "ERROR: ${HOSTNAME} has no disko disk config — can't provision"; exit 1; }
echo "  Disk device: ${disk_device}"

# FIX 4: remote deploys as jaide need the store to trust her.
trusted=$(nix eval --json ".#nixosConfigurations.${HOSTNAME}.config.nix.settings.\"trusted-users\"" 2>/dev/null || echo "[]")
if ! echo "${trusted}" | grep -q '"jaide"'; then
  echo "ERROR: nix.settings.trusted-users for ${HOSTNAME} doesn't include \"jaide\"."
  echo "  Without it, the final deploy (nixos-rebuild --target-host jaide@) fails:"
  echo "  the target's nix daemon rejects our locally-built unsigned closure."
  exit 1
fi

# SSH to root@target must work. If SSHPASS is set, install our key first.
if ! ssh ${SSH_OPTS} -o BatchMode=yes "root@${IP}" true 2>/dev/null; then
  if [ -n "${SSHPASS:-}" ]; then
    echo "  Installing SSH key on root@${IP} via password..."
    sshpass -e ssh-copy-id ${SSH_OPTS} -i "${HOME}/.ssh/id_ed25519.pub" "root@${IP}" >/dev/null
  fi
fi
ssh ${SSH_OPTS} -o BatchMode=yes "root@${IP}" true \
  || { echo "ERROR: can't SSH to root@${IP} (set SSHPASS or install a key)"; exit 1; }
echo "  SSH to root@${IP}: OK"

# FIX 3: the live ISO auto-suspends on idle and drops the NIC mid-copy.
echo "  Masking suspend targets on the installer (runtime only)..."
ssh ${SSH_OPTS} "root@${IP}" \
  "systemctl mask --runtime sleep.target suspend.target hibernate.target hybrid-sleep.target" \
  || echo "  WARNING: could not mask sleep targets — watch for the target dozing off"

# ── Step 1 (FIX 1): secrets FIRST — generate + register + re-encrypt ──
echo ""
echo "── Step 1/6: sops host key — generate, register, re-encrypt ──"

if [ ! -f "${AGE_KEY_FILE}" ]; then
  age-keygen -o "${AGE_KEY_FILE}" 2>/dev/null
  chmod 600 "${AGE_KEY_FILE}"
fi
AGE_PUBKEY=$(age-keygen -y "${AGE_KEY_FILE}")
echo "  Host age key: ${AGE_PUBKEY}"

python3 - "${SOPS_YAML}" "${HOSTNAME}" "${AGE_PUBKEY}" << 'PYEOF'
import sys, re

path, hostname, pubkey = sys.argv[1], sys.argv[2], sys.argv[3]
anchor = f"&host_{hostname}"

with open(path) as f:
    content = f.read()

# 1. Add or update the anchor line in the keys: section.
anchor_line = f"  - {anchor} {pubkey}"
anchor_re = re.compile(rf'^  - {re.escape(anchor)} .*$', re.MULTILINE)

if anchor_re.search(content):
    content = anchor_re.sub(anchor_line, content)
    print(f"  Updated existing {anchor} with new key.")
else:
    host_key_re = re.compile(r'^(  - &host_.*)$', re.MULTILINE)
    matches = list(host_key_re.finditer(content))
    if matches:
        last = matches[-1]
        content = content[:last.end()] + "\n" + anchor_line + content[last.end():]
    else:
        content = content.replace("creation_rules:", anchor_line + "\n\ncreation_rules:")
    print(f"  Added new {anchor}.")

# 2. Add *host_<hostname> to the shared + legacy creation rules (only).
ref_line = f"          - *host_{hostname}"
if ref_line not in content:
    lines = content.split("\n")
    new_lines = []
    current_rule = None
    in_key_group = False

    i = 0
    while i < len(lines):
        line = lines[i]

        m = re.match(r'\s*- path_regex:\s*(.+)', line)
        if m:
            current_rule = m.group(1)
            new_lines.append(line)
            i += 1
            continue

        if "key_groups:" in line and current_rule:
            in_key_group = True
            new_lines.append(line)
            i += 1
            continue

        if in_key_group and re.match(r'\s*- \*host_', line):
            new_lines.append(line)
            j = i + 1
            while j < len(lines) and lines[j].startswith("          - *host_"):
                new_lines.append(lines[j])
                i = j
                j += 1
            block = "\n".join(new_lines[-10:])
            if f"*host_{hostname}" not in block:
                if "shared" in current_rule or "secrets.yaml" in current_rule or "secrets\\.yaml" in current_rule:
                    new_lines.append(ref_line)
            i += 1
            continue

        if in_key_group and line and not line.startswith("          -") and not line.startswith("      - age:"):
            in_key_group = False
            current_rule = None

        new_lines.append(line)
        i += 1

    content = "\n".join(new_lines)
    print(f"  Added {hostname} to shared + legacy creation rules.")
else:
    print(f"  {hostname} already in creation rules.")

with open(path, "w") as f:
    f.write(content)
PYEOF

grep -q "&host_${HOSTNAME}" "${SOPS_YAML}" && grep -q "\*host_${HOSTNAME}" "${SOPS_YAML}" \
  || { echo "ERROR: .sops.yaml verification failed — check it manually"; exit 1; }
echo "  .sops.yaml updated + verified."

# Re-encryption identity: SOPS_AGE_KEY_FILE (YubiKey) or this host's own key.
if [ -n "${SOPS_AGE_KEY_FILE:-}" ] && [ -f "${SOPS_AGE_KEY_FILE}" ]; then
  echo "  Re-encrypting with SOPS_AGE_KEY_FILE (touch YubiKey if prompted)..."
elif sudo -n true 2>/dev/null; then
  LOCAL_HOST_KEY=$(mktemp)
  sudo install -m 600 -o "$(id -u)" -g "$(id -g)" /var/lib/sops-nix/key.txt "${LOCAL_HOST_KEY}"
  export SOPS_AGE_KEY_FILE="${LOCAL_HOST_KEY}"
  echo "  Re-encrypting with this host's local sops key (via sudo)..."
else
  echo "ERROR: no way to decrypt secrets: set SOPS_AGE_KEY_FILE (YubiKey) or cache sudo (sudo -v)."
  exit 1
fi

cd "${SECRETS_REPO}"
find secrets -name '*.yaml' -print0 | while IFS= read -r -d '' f; do
  echo "  Updating ${f}..."
  sops updatekeys --yes "${f}" || { echo "ERROR: updatekeys failed for ${f}"; exit 1; }
done
[ -f secrets.yaml ] && { echo "  Updating secrets.yaml..."; sops updatekeys --yes secrets.yaml; }

# Prove the NEW host key can actually decrypt before we install anything.
echo "  Verifying the new host key can decrypt every file..."
find secrets -name '*.yaml' -print0 | while IFS= read -r -d '' f; do
  SOPS_AGE_KEY_FILE="${AGE_KEY_FILE}" sops decrypt "${f}" >/dev/null \
    || { echo "ERROR: new host key cannot decrypt ${f}"; exit 1; }
done
[ -f secrets.yaml ] && SOPS_AGE_KEY_FILE="${AGE_KEY_FILE}" sops decrypt secrets.yaml >/dev/null
echo "  All files decrypt with the new host key."

git add .sops.yaml secrets/ secrets.yaml 2>/dev/null || true
if git diff --cached --quiet; then
  echo "  No secrets changes to commit (host was already registered)."
else
  git commit -m "Add ${HOSTNAME} host age key to sops"
fi
git push origin main 2>&1 || { echo "ERROR: secrets push failed — the flake input must see this commit"; exit 1; }

cd "${FLAKE_ROOT}"
nix flake lock --update-input nixos-secrets

# Stage the private key for first-boot activation.
rm -rf "${EXTRA_FILES}"
mkdir -p "${EXTRA_FILES}/var/lib/sops-nix"
install -m 600 "${AGE_KEY_FILE}" "${EXTRA_FILES}/var/lib/sops-nix/key.txt"
echo "  Staged host key for --extra-files."

# ── Step 2: nixos-anywhere (no reboot — verify boot first) ──────────
echo ""
echo "── Step 2/6: nixos-anywhere (wipe + install, NO reboot yet) ──"
echo "  This WIPES ${disk_device} on ${IP}. Proceeding in 5 seconds..."
sleep 5

HW_CONFIG="${FLAKE_ROOT}/hosts/${HOSTNAME}/hardware-configuration.nix"
HW_ARGS=()
# FIX 5: only generate if missing — regeneration drops nothing host-specific
# ONLY because we keep initrd force-loads in tracked host modules. Never
# regenerate over an existing file unattended.
if [ ! -f "${HW_CONFIG}" ]; then
  HW_ARGS=(--generate-hardware-config nixos-generate-config "${HW_CONFIG}")
  echo "  No hardware-configuration.nix — will generate one."
fi

nix run "${FLAKE_ROOT}#nixos-anywhere" -- \
  --flake "${FLAKE_ROOT}#${HOSTNAME}" \
  --target-host "root@${IP}" \
  --phases kexec,disko,install \
  --extra-files "${EXTRA_FILES}" \
  "${HW_ARGS[@]}"

echo "  Install complete (target still running the installer)."

# ── Step 3 (FIX 2): verify the boot path BEFORE rebooting ───────────
echo ""
echo "── Step 3/6: Verifying bootloader + EFI NVRAM entry ──"
ssh ${SSH_OPTS} "root@${IP}" 'bash -s' << 'REMOTEEOF'
set -euo pipefail
ESP_DEV=$(findmnt -n -o SOURCE /mnt/boot 2>/dev/null || true)
[ -n "${ESP_DEV}" ] || { echo "ERROR: /mnt/boot not mounted"; exit 1; }

# systemd-boot binary must be on the ESP (nixos-anywhere's chroot can fail
# this silently when efivars isn't available).
if [ ! -f /mnt/boot/EFI/systemd/systemd-bootx64.efi ]; then
  echo "  systemd-boot binary missing from ESP — running bootctl install"
  bootctl install --esp-path=/mnt/boot
fi

PARTUUID=$(blkid -o value -s PARTUUID "${ESP_DEV}")
DISK_DEV="/dev/$(lsblk -n -o PKNAME "${ESP_DEV}")"
echo "  ESP: ${ESP_DEV} PARTUUID=${PARTUUID}"

# Drop stale "Linux Boot Manager" entries pointing at other partitions.
for num in $(efibootmgr -v | grep -oP '^Boot\K[0-9A-F]{4}(?=\*? +Linux Boot Manager)'); do
  GUID=$(efibootmgr -v | grep -E "^Boot${num}\*? +Linux Boot Manager" | grep -oP 'GPT,\K[0-9a-f-]{36}' | head -1 || true)
  if [ "${GUID,,}" != "${PARTUUID,,}" ]; then
    echo "  Deleting stale entry Boot${num} (points at ${GUID:-nothing})"
    efibootmgr -b "${num}" -B >/dev/null
  fi
done

# Ensure an entry exists for OUR ESP and is first in the boot order.
KEEP=$(efibootmgr -v | grep "Linux Boot Manager" | grep -c "${PARTUUID}" || true)
if [ "${KEEP}" = "0" ]; then
  echo "  Creating NVRAM entry for the new ESP"
  efibootmgr -c -d "${DISK_DEV}" -p 1 -L "Linux Boot Manager" -l '\EFI\systemd\systemd-bootx64.efi' >/dev/null
fi
ENTRY=$(efibootmgr -v | grep "Linux Boot Manager" | grep "${PARTUUID}" | grep -oP '^Boot\K[0-9A-F]{4}' | head -1)
OTHERS=$(efibootmgr | grep -oP '^Boot\K[0-9A-F]{4}(?=\*)' | grep -v "^${ENTRY}$" | paste -sd, -)
efibootmgr -o "${ENTRY}${OTHERS:+,${OTHERS}}" >/dev/null

echo "  Boot entry: Boot${ENTRY} -> ${PARTUUID} (first in BootOrder)"
grep -q '^default ' /mnt/boot/loader/loader.conf || { echo "ERROR: no default boot entry in loader.conf"; exit 1; }
echo "  Boot path verified."
REMOTEEOF

# ── Step 4: reboot + wait for the installed system ──────────────────
echo ""
echo "── Step 4/6: Rebooting into the installed system ──"
ssh ${SSH_OPTS} "root@${IP}" "nohup reboot >/dev/null 2>&1 &" || true

echo "  Polling jaide@${IP} SSH (up to 300s)..."
up=0
for i in $(seq 1 60); do
  if ssh ${SSH_OPTS} -o BatchMode=yes "jaide@${IP}" "echo ok" 2>/dev/null | grep -q ok; then
    up=1
    echo "  Installed system is up (after ~$((i*5))s)."
    break
  fi
  sleep 5
done
if [ "${up}" != "1" ]; then
  echo "ERROR: ${HOSTNAME} did not come back on SSH within 300s."
  echo "  Check the console. If the boot failed, boot the ISO via the boot"
  echo "  menu (F7/F11) and inspect /mnt/boot + efibootmgr -v."
  exit 1
fi

# ── Step 5: verify activation actually completed (secrets!) ─────────
echo ""
echo "── Step 5/6: Verifying first activation (secrets, services) ──"
ssh ${SSH_OPTS} -o BatchMode=yes "jaide@${IP}" '
  echo "  hostname: $(hostname)"
  echo "  secrets:  $(ls /run/secrets/ 2>/dev/null | tr "\n" " ")"
  echo "  failed units: $(systemctl --failed --no-legend | wc -l)"
  [ -f /run/secrets/ssh_key ] || { echo "ERROR: /run/secrets/ssh_key missing — sops activation failed"; exit 1; }
'

# ── Step 6: first deploy (syncs to the latest flake state) ──────────
echo ""
echo "── Step 6/6: First deploy via jaide@ (local build, remote switch) ──"
nixos-rebuild switch \
  --flake ".#${HOSTNAME}" \
  --target-host "jaide@${IP}" \
  --use-remote-sudo \
  --use-substitutes

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ${HOSTNAME} provisioned, booted, and verified!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "  Next steps:"
echo "    1. SSH in:  ssh jaide@${IP}"
echo "    2. Change the initial password:  passwd"
echo "    3. Verify secrets:  ls /run/secrets/"
echo "    4. Commit:  git add -A && git commit (flake.lock + hardware-config)"
echo ""
echo "  For future deploys:"
echo "    just deploy-remote ${HOSTNAME} ${IP}"
