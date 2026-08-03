#!/usr/bin/env bash
# bootstrap-host.sh — full initial provisioning of a NixOS host from this flake.
#
# Does everything end-to-end from the local machine:
#   1. nixos-anywhere — wipes the target disk, installs NixOS, reboots.
#   2. Waits for the host to come back up on SSH.
#   3. Retrieves the auto-generated sops age key from /var/lib/sops-nix/key.txt.
#   4. Registers it in ~/nixos-secrets/.sops.yaml as &host_<hostname>.
#   5. Re-encrypts all secret files so the new host can decrypt them.
#   6. Commits + pushes the secrets repo.
#   7. Updates the nixos-secrets flake lock in ~/nixos.
#   8. First deploy: builds the closure LOCALLY (fast, big CPU here),
#      copies the store paths to the target, activates remotely via
#      jaide@ + sudo (no root SSH needed).
#
# Prerequisites:
#   - Target booted from a NixOS installer USB (or kexec'd into nixos).
#   - Target reachable at <ip> as root with SSH (installer default).
#   - The host exists in the flake with a disko disk-layout.nix.
#   - ~/nixos-secrets cloned and SOPS_AGE_KEY_FILE set (YubiKey plugged in).
#   - This machine has the SSH key that the target will authorize for jaide
#     (the sops-deployed key is not on the target yet during provisioning;
#     nixos-anywhere injects it from the installer's authorized_keys).
#
# Usage:
#   just bootstrap UwU-Server 192.168.1.50
#   scripts/bootstrap-host.sh UwU-Server 192.168.1.50
set -euo pipefail

# ── Args ────────────────────────────────────────────────────────────
HOSTNAME="${1:?usage: bootstrap-host.sh <hostname> <ip>}"
IP="${2:?usage: bootstrap-host.sh <hostname> <ip>}"

# Resolve paths relative to the flake root (two dirs up from this script).
FLAKE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_REPO="${HOME}/nixos-secrets"
SOPS_YAML="${SECRETS_REPO}/.sops.yaml"

echo "════════════════════════════════════════════════════════════════"
echo "  Bootstrap: ${HOSTNAME} @ ${IP}"
echo "  Flake:     ${FLAKE_ROOT}"
echo "  Secrets:   ${SECRETS_REPO}"
echo "════════════════════════════════════════════════════════════════"

# ── Sanity checks ───────────────────────────────────────────────────
[ -f "${SOPS_YAML}" ] || { echo "ERROR: ${SOPS_YAML} not found — clone nixos-secrets first"; exit 1; }
[ -n "${SOPS_AGE_KEY_FILE:-}" ] || { echo "ERROR: SOPS_AGE_KEY_FILE not set — insert YubiKey and export it"; exit 1; }
[ -f "${SOPS_AGE_KEY_FILE}" ] || { echo "ERROR: ${SOPS_AGE_KEY_FILE} not found — run age-plugin-yubikey -g"; exit 1; }

# Check the host exists in the flake.
nix eval --json ".#nixosConfigurations.${HOSTNAME}.config.networking.hostName" >/dev/null 2>&1 \
  || { echo "ERROR: ${HOSTNAME} not found in flake nixosConfigurations"; exit 1; }

# Check the host has a disko config (required for nixos-anywhere).
disk_device=$(nix eval --json ".#nixosConfigurations.${HOSTNAME}.config.disko.devices.disk.main.device" 2>/dev/null || echo "")
[ -n "${disk_device}" ] || { echo "ERROR: ${HOSTNAME} has no disko disk config — can't provision"; exit 1; }
echo "  Disk device: ${disk_device}"

# ── Step 1: nixos-anywhere ──────────────────────────────────────────
echo ""
echo "── Step 1/7: nixos-anywhere (wipe + install + reboot) ──"
echo "  This WIPES ${disk_device} on ${IP}. Proceeding in 5 seconds..."
sleep 5

nix run "${FLAKE_ROOT}#nixos-anywhere" -- \
  --flake "${FLAKE_ROOT}#${HOSTNAME}" \
  --target-host "root@${IP}" \
  --generate-hardware-config nixos-generate-config "${FLAKE_ROOT}/hosts/${HOSTNAME}/hardware-configuration.nix"

echo "  nixos-anywhere complete — host should be rebooting."

# ── Step 2: Wait for SSH to come back ───────────────────────────────
echo ""
echo "── Step 2/7: Waiting for ${HOSTNAME} (${IP}) to come back on SSH ──"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=${HOME}/.ssh/known_hosts -o ConnectTimeout=5 -o ServerAliveInterval=10"

echo "  Polling SSH (up to 120s)..."
for i in $(seq 1 24); do
  if ssh ${SSH_OPTS} "jaide@${IP}" "echo ok" 2>/dev/null | grep -q ok; then
    echo "  SSH is up (after ~$((i*5))s)."
    break
  fi
  if [ "$i" -eq 24 ]; then
    echo "ERROR: ${HOSTNAME} did not come back on SSH within 120s."
    echo "  Check the host's console. The install may have succeeded but"
    echo "  SSH (jaide@) might not be reachable yet. If the host is up,"
    echo "  you can skip to step 3 manually:"
    echo "    scp jaide@${IP}:/var/lib/sops-nix/key.txt /tmp/${HOSTNAME}-age.key"
    exit 1
  fi
  sleep 5
done

# ── Step 3: Retrieve the sops age key ───────────────────────────────
echo ""
echo "── Step 3/7: Retrieving sops age key from ${HOSTNAME} ──"
AGE_KEY_FILE="/tmp/${HOSTNAME}-age.key"
scp ${SSH_OPTS} "jaide@${IP}:/var/lib/sops-nix/key.txt" "${AGE_KEY_FILE}" 2>/dev/null \
  || scp ${SSH_OPTS} "jaide@${IP}:/var/lib/sops-nix/key.txt" "${AGE_KEY_FILE}"  # retry without grep

# The key file has a comment line + the age1... public key. Extract just the pubkey.
AGE_PUBKEY=$(grep '^age1' "${AGE_KEY_FILE}" | head -1)
[ -n "${AGE_PUBKEY}" ] || { echo "ERROR: no age1 key found in retrieved key file"; cat "${AGE_KEY_FILE}"; exit 1; }
echo "  Host age key: ${AGE_PUBKEY}"

# ── Step 4: Register in .sops.yaml ──────────────────────────────────
echo ""
echo "── Step 4/7: Registering host key in .sops.yaml ──"

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
    # Update existing anchor with the new key.
    content = anchor_re.sub(anchor_line, content)
    print(f"  Updated existing {anchor} with new key.")
else:
    # Insert after the last &host_ line, or before creation_rules: if none.
    host_key_re = re.compile(r'^(  - &host_.*)$', re.MULTILINE)
    matches = list(host_key_re.finditer(content))
    if matches:
        last = matches[-1]
        content = content[:last.end()] + "\n" + anchor_line + content[last.end():]
    else:
        content = content.replace("creation_rules:", anchor_line + "\n\ncreation_rules:")
    print(f"  Added new {anchor}.")

# 2. Add *host_<hostname> to the shared + legacy creation rules (only).
#    Per-host rules get only their own key, so we don't touch those.
ref_line = f"          - *host_{hostname}"
if ref_line not in content:
    lines = content.split("\n")
    new_lines = []
    current_rule = None
    in_key_group = False

    i = 0
    while i < len(lines):
        line = lines[i]

        # Track which creation rule we're in.
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
            # Consume all consecutive *host_ lines, then add ours if the
            # rule is shared or legacy and we're not already present.
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

echo "  .sops.yaml updated."
if grep -q "&host_${HOSTNAME}" "${SOPS_YAML}" && grep -q "\*host_${HOSTNAME}" "${SOPS_YAML}"; then
  echo "  OK: anchor + references present."
else
  echo "  WARNING: verification failed — check .sops.yaml manually."
fi

# ── Step 5: Re-encrypt secrets ──────────────────────────────────────
echo ""
echo "── Step 5/7: Re-encrypting secret files for ${HOSTNAME} ──"
echo "  (Touch your YubiKey when prompted for each file.)"
cd "${SECRETS_REPO}"

# Re-encrypt every secrets file so the new host key is included.
find secrets -name '*.yaml' -print0 | while IFS= read -r -d '' f; do
  echo "  Updating ${f}..."
  sops updatekeys --yes "${f}" || echo "  WARNING: updatekeys failed for ${f} (maybe no keys match yet)"
done

# Also update the root secrets.yaml if it exists.
[ -f secrets.yaml ] && { echo "  Updating secrets.yaml..."; sops updatekeys --yes secrets.yaml || true; }

echo "  Re-encryption complete."

# ── Step 6: Commit + push secrets repo ──────────────────────────────
echo ""
echo "── Step 6/7: Committing + pushing nixos-secrets ──"
git add .sops.yaml secrets/ secrets.yaml 2>/dev/null || true
if git diff --cached --quiet; then
  echo "  No changes to commit (host was already registered)."
else
  git commit -m "Add ${HOSTNAME} host age key to sops"
fi
git push origin main 2>&1 || { echo "  WARNING: push failed — push manually when ready"; }

cd "${FLAKE_ROOT}"

# ── Step 7: Update flake lock + first deploy ────────────────────────
echo ""
echo "── Step 7/7: Update nixos-secrets flake lock + first deploy ──"
echo "  Updating nixos-secrets input..."
nix flake lock --update-input nixos-secrets

echo ""
echo "  Building closure locally and deploying to ${HOSTNAME}..."
echo "  (Build runs HERE for speed; only store paths are copied.)"
nixos-rebuild switch \
  --flake ".#${HOSTNAME}" \
  --target-host "jaide@${IP}" \
  --use-remote-sudo \
  --use-substitutes

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ${HOSTNAME} provisioned and deployed successfully!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "  Next steps:"
echo "    1. SSH in:  ssh jaide@${IP}"
echo "    2. Change the initial password:  passwd"
echo "    3. Verify secrets:  ls /run/secrets/"
echo "    4. Commit the flake.lock update:  git add flake.lock && git commit"
echo ""
echo "  For future deploys:"
echo "    just deploy-remote ${HOSTNAME} ${IP}"