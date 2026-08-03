#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/scripts/bootstrap-host.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# shellcheck source=../scripts/bootstrap-host.sh
BOOTSTRAP_HOST_LIB_ONLY=1 source "$SCRIPT"

ssh-keygen -q -t ed25519 -N '' -f "$work/host-key"
ssh-keygen -q -t ed25519 -N '' -f "$work/attacker-key"
{
  printf '192.0.2.10 %s\n' "$(<"$work/host-key.pub")"
  printf '192.0.2.10 %s\n' "$(<"$work/attacker-key.pub")"
} >"$work/known_hosts"
fingerprint=$(ssh-keygen -E sha256 -lf "$work/host-key.pub" | cut -d ' ' -f 2)

INSTALLER_HOST_FINGERPRINT=$fingerprint confirm_installer_host_key "$work/known_hosts" 192.0.2.10
[[ $(wc -l <"$work/known_hosts") -eq 1 ]] \
  || { echo 'FAIL: fingerprint confirmation retained unverified host keys' >&2; exit 1; }
read -r _ retained_type retained_blob _ <"$work/known_hosts"
read -r expected_type expected_blob _ <"$work/host-key.pub"
[[ "$retained_type:$retained_blob" == "$expected_type:$expected_blob" ]] \
  || { echo 'FAIL: fingerprint confirmation retained the wrong key' >&2; exit 1; }
if INSTALLER_HOST_FINGERPRINT='SHA256:not-the-target' \
  confirm_installer_host_key "$work/known_hosts" 192.0.2.10 2>/dev/null; then
  echo 'FAIL: mismatched out-of-band host fingerprint was accepted' >&2
  exit 1
fi

python3 - "$SCRIPT" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
confirm = text.find('confirm_installer_host_key "$KNOWN_HOSTS" "$IP"')
password = text.find('sshpass -e ssh-copy-id')
if confirm < 0 or password < 0 or confirm > password:
    raise SystemExit('FAIL: password-bearing SSH can occur before host-key confirmation')
if 'INSTALLER_KNOWN_HOSTS_FILE' not in text:
    raise SystemExit('FAIL: no pre-provisioned known-hosts path is supported')
PY

echo 'bootstrap authenticity regressions: PASS'
