#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat >"$work/old" <<'EOF'
192.168.1.10 ssh-ed25519 AAAATESTSAME
192.168.1.10 ssh-rsa AAAATESTOLD
EOF
cat >"$work/same" <<'EOF'
192.168.1.20 ssh-ed25519 AAAATESTSAME
192.168.1.20 ssh-ed25519 AAAATESTATTACKER
EOF
cat >"$work/other" <<'EOF'
192.168.1.20 ssh-ed25519 AAAATESTOTHER
EOF

mkdir "$work/bin"
cat >"$work/bin/ip" <<'STUB'
set -euo pipefail
case "$*" in
  '-j route get 192.168.1.10')
    printf '%s\n' '[{"dev":"eth0","prefsrc":"192.168.1.5"}]'
    ;;
  '-j route get 203.0.113.10')
    printf '%s\n' '[{"dev":"eth0","prefsrc":"192.168.1.5"}]'
    ;;
  '-j route get 192.168.1.11')
    printf '%s\n' '[{"dev":"eth0","prefsrc":"192.168.1.5","gateway":"192.168.1.1"}]'
    ;;
  '-j address show dev eth0')
    printf '%s\n' '[{"addr_info":[{"family":"inet","local":"192.168.1.5","prefixlen":24}]}]'
    ;;
  '-j neigh')
    printf '%s\n' '[{"dst":"192.168.1.10","lladdr":"aa:bb:cc:dd:ee:ff","state":["FAILED"]},{"dst":"192.168.1.20","lladdr":"02:11:22:33:44:55","state":["REACHABLE"]},{"dst":"192.168.1.30","lladdr":"66:77:88:99:aa:bb","state":["STALE"]},{"dst":"192.168.2.40","lladdr":"cc:dd:ee:ff:00:11","state":["REACHABLE"]}]'
    ;;
  *) exit 2 ;;
esac
STUB
content=$(<"$work/bin/ip")
printf '#!%s\n%s\n' "$(command -v bash)" "$content" >"$work/bin/ip"
chmod +x "$work/bin/ip"

export PATH="$work/bin:$PATH"
# shellcheck source=../scripts/bootstrap-host.sh
BOOTSTRAP_HOST_LIB_ONLY=1 source "$ROOT/scripts/bootstrap-host.sh"

host_key_sets_overlap "$work/old" "$work/same"
if host_key_sets_overlap "$work/old" "$work/other"; then
  echo 'FAIL: unrelated SSH host keys were accepted' >&2
  exit 1
fi
filter_host_keys_to_overlap "$work/old" "$work/same" "$work/filtered"
[[ $(wc -l <"$work/filtered") -eq 1 ]] \
  || { echo 'FAIL: DHCP continuity retained unverified candidate keys' >&2; exit 1; }
grep -q '^192\.168\.1\.20 ssh-ed25519 AAAATESTSAME$' "$work/filtered" \
  || { echo 'FAIL: DHCP continuity did not retain the exact trusted key' >&2; exit 1; }

[[ $(network_cidr_for_target 192.168.1.10) == 192.168.1.0/24 ]] \
  || { echo 'FAIL: direct target CIDR was not derived' >&2; exit 1; }
if network_cidr_for_target 203.0.113.10 >/dev/null 2>&1; then
  echo 'FAIL: routed VPS target was mistaken for a directly connected CIDR' >&2
  exit 1
fi
if network_cidr_for_target 192.168.1.11 >/dev/null 2>&1; then
  echo 'FAIL: same-CIDR target routed through a gateway was treated as directly connected' >&2
  exit 1
fi
mapfile -t neighbors < <(neighbor_ips_in_cidr 192.168.1.0/24)
[[ " ${neighbors[*]} " == *' 192.168.1.20 '* \
  && " ${neighbors[*]} " == *' 192.168.1.30 '* \
  && " ${neighbors[*]} " != *' 192.168.1.10 '* \
  && " ${neighbors[*]} " != *' 192.168.2.40 '* ]] \
  || { echo 'FAIL: CIDR candidate discovery depends on the installer MAC or includes unusable neighbors' >&2; exit 1; }

python3 - "$ROOT/scripts/bootstrap-host.sh" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
postboot = text[text.index('echo "Waiting up to 300 seconds'):]
if 'target_mac' in postboot or 'neighbor_for_mac' in postboot:
    raise SystemExit('FAIL: post-boot discovery still depends on the installer MAC')
if 'if [[ -n "$target_cidr" ]]; then' not in postboot:
    raise SystemExit('FAIL: routed targets do not guard LAN-only CIDR discovery')
if 'candidates=("$IP")' not in postboot:
    raise SystemExit('FAIL: routed targets do not retry their original pinned address')
guard = postboot.index('if [[ -n "$target_cidr" ]]; then')
nmap = postboot.index('nmap -sn "$target_cidr"')
neighbor = postboot.index('neighbor_ips_in_cidr "$target_cidr"')
guard_end = postboot.index('\n  fi', guard)
if not guard < nmap < neighbor < guard_end:
    raise SystemExit('FAIL: LAN scan or neighbor discovery escapes the direct-target guard')
PY

echo 'bootstrap network regressions: PASS'
