#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

bash tests/bootstrap-host-regressions.sh
bash tests/justfile-argument-regressions.sh
python3 tests/ad-lab-name-regressions.py
python3 tests/register-sops-host-regressions.py
python3 tests/user-password-regressions.py
python3 tests/net-report-wifi-scan-regressions.py

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

metadata=$(nix flake metadata --no-write-lock-file 2>&1)
if grep -q "override for a non-existent input" <<<"$metadata"; then
  fail "flake metadata still reports a non-existent input override"
fi

if git grep -nE 'specialArgs|extraSpecialArgs|_module\.args' -- '*.nix'; then
  fail "Dendritic lower-level argument pass-through is still present"
fi

git grep -q 'lazyAttrsOf lib.types.deferredModule' -- modules/options.nix \
  || fail "nixos.modules is not typed as lazyAttrsOf deferredModule"

if git grep -n 'device = "/dev/sda"' -- '*.nix'; then
  fail "an exported disk layout still targets unstable /dev/sda"
fi

if git grep -n 'nix-collect-garbage --delete-old' -- Justfile '*.nix'; then
  fail "rollback-destroying garbage-collection command is still present"
fi

if git grep -n 'system.activationScripts.flatpakManagement' -- '*.nix'; then
  fail "Flatpak network operations still run during activation"
fi

nix fmt -- --check . >/dev/null

for host in UwU TSBW-W01800; do
  firewall=$(nix eval --json ".#nixosConfigurations.\"$host\".config.networking.firewall.enable")
  assert_eq true "$firewall" "$host built-in firewall"

  has_awg=$(nix eval --json ".#nixosConfigurations.\"$host\".config.networking.wg-quick.interfaces" --apply 'x: builtins.hasAttr "awg0" x')
  assert_eq false "$has_awg" "$host unconfigured AWG interface"

  ssh=$(nix eval --json ".#nixosConfigurations.\"$host\".config.services.openssh.enable")
  assert_eq false "$ssh" "$host unconfigured SSH service"

done

owo_exported=$(nix eval --json '.#nixosConfigurations' --apply 'x: builtins.hasAttr "OwO-Family" x')
assert_eq false "$owo_exported" "unsafe placeholder OwO-Family export"

packages=$(nix eval --json '.#packages.x86_64-linux' --apply builtins.attrNames)
for package in macrotool-gtk4 nixos-anywhere; do
  [[ "$packages" == *"\"$package\""* ]] || fail "missing package output: $package"
done

tsbw_personal_services=$(nix eval --json '.#nixosConfigurations.TSBW-W01800' --apply 'x: {
  gdrive = builtins.hasAttr "rclone-gdrive-sync" x.config.systemd.user.services;
  virtualCamera = builtins.elem "v4l2loopback" x.config.boot.kernelModules;
}')
[[ "$tsbw_personal_services" == *'"gdrive":false'* ]] || fail "gdrive sync leaked onto TSBW"
[[ "$tsbw_personal_services" == *'"virtualCamera":false'* ]] || fail "virtual-camera kernel module leaked onto TSBW"

groups=$(nix eval --json '.#nixosConfigurations.UwU.config.users.users.jaide.extraGroups')
python3 - "$groups" <<'PY'
import json
import sys

groups = json.loads(sys.argv[1])
if "net-report" not in groups:
    raise SystemExit("FAIL: jaide is not in the dedicated net-report group")
if "root" in groups:
    raise SystemExit("FAIL: jaide must not be added to the root group")
PY

for wrapper in net-report-ip net-report-iw net-report-tcpdump net-report-aireplay; do
  group=$(nix eval --raw ".#nixosConfigurations.UwU.config.security.wrappers.$wrapper.group")
  assert_eq net-report "$group" "$wrapper group"
done

printf 'review regressions: PASS\n'
