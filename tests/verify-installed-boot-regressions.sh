#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/scripts/verify-installed-boot.sh"
[[ -x "$SCRIPT" ]] || { echo 'FAIL: installed-boot verifier is missing or not executable' >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
root="$work/target"
bin="$work/bin"
mkdir -p "$bin" "$root/boot/EFI/systemd" "$root/boot/EFI/nixos" \
  "$root/boot/loader/entries" "$root/nix/store/00000000000000000000000000000000-test-system" \
  "$root/nix/store/11111111111111111111111111111111-test-kernel" "$root/nix/store/22222222222222222222222222222222-test-initrd" \
  "$root/nix/var/nix/profiles" "$work/efivars"
: >"$root/boot/EFI/systemd/systemd-bootx64.efi"
printf 'kernel payload\n' >"$root/boot/EFI/nixos/kernel.efi"
printf 'initrd payload\n' >"$root/boot/EFI/nixos/initrd.efi"
cp "$root/boot/EFI/nixos/kernel.efi" "$root/nix/store/11111111111111111111111111111111-test-kernel/bzImage"
cp "$root/boot/EFI/nixos/initrd.efi" "$root/nix/store/22222222222222222222222222222222-test-initrd/initrd"
: >"$root/nix/store/00000000000000000000000000000000-test-system/init"
cat >"$root/nix/store/00000000000000000000000000000000-test-system/boot.json" <<'EOF'
{
  "org.nixos.bootspec.v1": {
    "init": "/nix/store/00000000000000000000000000000000-test-system/init",
    "initrd": "/nix/store/22222222222222222222222222222222-test-initrd/initrd",
    "kernel": "/nix/store/11111111111111111111111111111111-test-kernel/bzImage",
    "toplevel": "/nix/store/00000000000000000000000000000000-test-system"
  }
}
EOF
ln -s system-1-link "$root/nix/var/nix/profiles/system"
ln -s /nix/store/00000000000000000000000000000000-test-system "$root/nix/var/nix/profiles/system-1-link"
printf 'default nixos-test.conf\n' >"$root/boot/loader/loader.conf"
cat >"$root/boot/loader/entries/nixos-test.conf" <<'EOF'
title NixOS test
linux /EFI/nixos/kernel.efi
initrd /EFI/nixos/initrd.efi
options init=/nix/store/00000000000000000000000000000000-test-system/init quiet
EOF

fake_disk="$work/fake-disk"
fake_esp="$work/fake-esp"
other_disk="$work/other-disk"
: >"$fake_disk"
: >"$fake_esp"
: >"$other_disk"

cat >"$bin/findmnt" <<'STUB'
set -euo pipefail
printf '%s %s %s\n' "${FINDMNT_SOURCE:-$FAKE_ESP}" "$TARGET_ROOT/boot" "${FINDMNT_FSTYPE:-vfat}"
STUB
cat >"$bin/lsblk" <<'STUB'
set -euo pipefail
case "$*" in
  '-npo PKNAME '*)
    [[ "${*: -1}" == "$FAKE_ESP" ]] && printf '%s\n' "$FAKE_DISK" || printf '%s\n' "$OTHER_DISK"
    ;;
  '-no PARTN '*) printf '%s\n' 2 ;;
  *) exit 2 ;;
esac
STUB
cat >"$bin/blkid" <<'STUB'
set -euo pipefail
printf '%s\n' "$PARTUUID"
STUB
cat >"$bin/efibootmgr" <<'STUB'
set -euo pipefail
state=$(<"$EFI_STATE")
case "${1:-}" in
  -c)
    : >"$CREATE_CALLED"
    [[ ${IGNORE_CREATE:-0} == 1 ]] || printf 'created\n' >"$EFI_STATE"
    ;;
  -o)
    [[ ${IGNORE_BOOTORDER:-0} == 1 ]] || printf 'ordered:%s\n' "$2" >"$EFI_STATE"
    ;;
  -v|'')
    case "$state" in
      initial)
        printf 'BootOrder: 0008,0001\nBoot0008* Evil HD(2,GPT,wrong,0x800,0x1000)/File(\\EFI\\evil.efi) note %s %s\nBoot0001* Other\n' "$PARTUUID" '\EFI\systemd\systemd-bootx64.efi'
        ;;
      created)
        printf 'BootOrder: 0001\nBoot0009* Linux Boot Manager HD(2,GPT,%s,0x800,0x1000)/\\File(\\EFI\\systemd\\systemd-bootx64.efi)\nBoot0001* Other\n' "$PARTUUID"
        ;;
      exact)
        printf 'BootOrder: 0009,0001\nBoot0009* Linux Boot Manager HD(2,GPT,%s,0x800,0x1000)/\\File(\\EFI\\systemd\\systemd-bootx64.efi)\nBoot0001* Other\n' "$PARTUUID"
        ;;
      direct)
        # efibootmgr 18 renders a valid EFI filepath node directly, without
        # the textual File(...) wrapper used by some firmware/tool versions.
        printf 'BootOrder: 0009,0001\nBoot0009* Linux Boot Manager HD(2,GPT,%s,0x800,0x1000)/\\EFI\\systemd\\systemd-bootx64.efi\nBoot0001* Other\n' "$PARTUUID"
        ;;
      inactive)
        printf 'BootOrder: 0009,0001\nBoot0009 Linux Boot Manager HD(2,GPT,%s,0x800,0x1000)/\\File(\\EFI\\systemd\\systemd-bootx64.efi)\nBoot0001* Other\n' "$PARTUUID"
        ;;
      ordered:*)
        order=${state#ordered:}
        printf 'BootOrder: %s\nBoot0009* Linux Boot Manager HD(2,GPT,%s,0x800,0x1000)/\\File(\\EFI\\systemd\\systemd-bootx64.efi)\nBoot0001* Other\n' "$order" "$PARTUUID"
        ;;
      malicious)
        printf 'BootOrder: 0009,0001\nBoot0009* Linux Boot Manager HD(2,GPT,%s,0x800,0x1000)/File(\\EFI\\evil.efi)/HD(3,GPT,aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee,0x1800,0x1000)/File(\\EFI\\systemd\\systemd-bootx64.efi)\nBoot0001* Other\n' "$PARTUUID"
        ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
STUB
for stub in "$bin"/*; do
  content=$(<"$stub")
  printf '#!%s\n%s\n' "$(command -v bash)" "$content" >"$stub"
  chmod +x "$stub"
done

export PATH="$bin:$PATH"
export TARGET_ROOT="$root"
export EFIVARS_PATH="$work/efivars"
export BOOT_VERIFY_TEST_MODE=1
export FAKE_DISK="$fake_disk"
export FAKE_ESP="$fake_esp"
export OTHER_DISK="$other_disk"
export PARTUUID='11111111-2222-3333-4444-555555555555'
export EFI_STATE="$work/efi-state"
export CREATE_CALLED="$work/create-called"

reset_efi() {
  printf 'initial\n' >"$EFI_STATE"
  rm -f "$CREATE_CALLED"
  unset IGNORE_BOOTORDER IGNORE_CREATE FINDMNT_SOURCE FINDMNT_FSTYPE
}

reset_efi
bash "$SCRIPT" "$fake_disk"
[[ -e "$CREATE_CALLED" ]] || { echo 'FAIL: absent NVRAM entry was not created' >&2; exit 1; }

adversarial_failures=0

reset_efi
printf 'exact\n' >"$EFI_STATE"
bash "$SCRIPT" "$fake_disk" >/dev/null
if [[ -e "$CREATE_CALLED" ]]; then
  echo 'FAIL: an exact pre-existing EFI entry was not reused' >&2
  ((adversarial_failures += 1))
fi

reset_efi
printf 'direct\n' >"$EFI_STATE"
bash "$SCRIPT" "$fake_disk" >/dev/null
if [[ -e "$CREATE_CALLED" ]]; then
  echo 'FAIL: an exact direct-path EFI entry was not reused' >&2
  ((adversarial_failures += 1))
fi

reset_efi
printf 'inactive\n' >"$EFI_STATE"
bash "$SCRIPT" "$fake_disk" >/dev/null
if [[ ! -e "$CREATE_CALLED" ]]; then
  echo 'FAIL: an inactive EFI entry was accepted as bootable' >&2
  ((adversarial_failures += 1))
fi

reset_efi
printf 'malicious\n' >"$EFI_STATE"
bash "$SCRIPT" "$fake_disk" >/dev/null
if [[ ! -e "$CREATE_CALLED" ]]; then
  echo 'FAIL: split EFI device-path nodes were reused as one exact ESP/loader path' >&2
  ((adversarial_failures += 1))
fi

reset_efi
cp "$root/nix/store/00000000000000000000000000000000-test-system/boot.json" "$work/good-boot.json"
cat >"$root/nix/store/00000000000000000000000000000000-test-system/boot.json" <<'EOF'
{
  "init": "/nix/store/00000000000000000000000000000000-test-system/init",
  "initrd": "/nix/store/22222222222222222222222222222222-test-initrd/initrd",
  "kernel": "/nix/store/11111111111111111111111111111111-test-kernel/bzImage",
  "toplevel": "/nix/store/00000000000000000000000000000000-test-system",
  "org.nixos.bootspec.v1": {
    "init": "/nix/store/33333333333333333333333333333333-wrong-system/init",
    "initrd": "/nix/store/44444444444444444444444444444444-wrong-initrd/initrd",
    "kernel": "/nix/store/55555555555555555555555555555555-wrong-kernel/bzImage",
    "toplevel": "/nix/store/33333333333333333333333333333333-wrong-system"
  }
}
EOF
if bash "$SCRIPT" "$fake_disk" >/dev/null 2>&1; then
  echo 'FAIL: decoy top-level JSON fields masked an incorrect bootspec object' >&2
  ((adversarial_failures += 1))
fi
mv "$work/good-boot.json" "$root/nix/store/00000000000000000000000000000000-test-system/boot.json"

reset_efi
mkdir -p "$root/outside-store-system"
: >"$root/outside-store-system/init"
cat >"$root/outside-store-system/boot.json" <<'EOF'
{
  "org.nixos.bootspec.v1": {
    "init": "/nix/store/../../outside-store-system/init",
    "initrd": "/nix/store/22222222222222222222222222222222-test-initrd/initrd",
    "kernel": "/nix/store/11111111111111111111111111111111-test-kernel/bzImage",
    "toplevel": "/nix/store/../../outside-store-system"
  }
}
EOF
rm "$root/nix/var/nix/profiles/system-1-link"
ln -s /nix/store/../../outside-store-system "$root/nix/var/nix/profiles/system-1-link"
cp "$root/boot/loader/entries/nixos-test.conf" "$work/good-entry-profile-traversal"
printf '%s\n' \
  'title NixOS test' \
  'linux /EFI/nixos/kernel.efi' \
  'initrd /EFI/nixos/initrd.efi' \
  'options init=/nix/store/../../outside-store-system/init quiet' \
  >"$root/boot/loader/entries/nixos-test.conf"
if bash "$SCRIPT" "$fake_disk" >/dev/null 2>&1; then
  echo 'FAIL: traversing system profile escaped /nix/store' >&2
  ((adversarial_failures += 1))
fi
mv "$work/good-entry-profile-traversal" "$root/boot/loader/entries/nixos-test.conf"
rm "$root/nix/var/nix/profiles/system-1-link"
ln -s /nix/store/00000000000000000000000000000000-test-system "$root/nix/var/nix/profiles/system-1-link"

reset_efi
mkdir -p "$root/outside-kernel"
cp "$root/nix/store/11111111111111111111111111111111-test-kernel/bzImage" "$root/outside-kernel/bzImage"
cp "$root/nix/store/00000000000000000000000000000000-test-system/boot.json" "$work/good-boot-kernel.json"
python3 - "$root/nix/store/00000000000000000000000000000000-test-system/boot.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    document = json.load(handle)
document["org.nixos.bootspec.v1"]["kernel"] = "/nix/store/../../outside-kernel/bzImage"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(document, handle)
PY
if bash "$SCRIPT" "$fake_disk" >/dev/null 2>&1; then
  echo 'FAIL: traversing kernel path escaped /nix/store' >&2
  ((adversarial_failures += 1))
fi
mv "$work/good-boot-kernel.json" "$root/nix/store/00000000000000000000000000000000-test-system/boot.json"

reset_efi
mkdir -p "$root/outside-initrd"
cp "$root/nix/store/22222222222222222222222222222222-test-initrd/initrd" "$root/outside-initrd/initrd"
cp "$root/nix/store/00000000000000000000000000000000-test-system/boot.json" "$work/good-boot-initrd.json"
python3 - "$root/nix/store/00000000000000000000000000000000-test-system/boot.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    document = json.load(handle)
document["org.nixos.bootspec.v1"]["initrd"] = "/nix/store/../../outside-initrd/initrd"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(document, handle)
PY
if bash "$SCRIPT" "$fake_disk" >/dev/null 2>&1; then
  echo 'FAIL: traversing initrd path escaped /nix/store' >&2
  ((adversarial_failures += 1))
fi
mv "$work/good-boot-initrd.json" "$root/nix/store/00000000000000000000000000000000-test-system/boot.json"

reset_efi
cp "$root/boot/loader/entries/nixos-test.conf" "$work/good-entry-conflict"
printf '%s\n' \
  'title NixOS test' \
  'linux /EFI/nixos/kernel.efi' \
  'initrd /EFI/nixos/initrd.efi' \
  'options init=/nix/store/00000000000000000000000000000000-test-system/init init=/nix/store/33333333333333333333333333333333-wrong-system/init quiet' \
  >"$root/boot/loader/entries/nixos-test.conf"
if bash "$SCRIPT" "$fake_disk" >/dev/null 2>&1; then
  echo 'FAIL: conflicting duplicate init= options were accepted' >&2
  ((adversarial_failures += 1))
fi
mv "$work/good-entry-conflict" "$root/boot/loader/entries/nixos-test.conf"

reset_efi
cp "$root/boot/loader/entries/nixos-test.conf" "$work/good-entry-duplicate"
printf '%s\n' \
  'title NixOS test' \
  'linux /EFI/nixos/kernel.efi' \
  'initrd /EFI/nixos/initrd.efi' \
  'options init=/nix/store/00000000000000000000000000000000-test-system/init init=/nix/store/00000000000000000000000000000000-test-system/init quiet' \
  >"$root/boot/loader/entries/nixos-test.conf"
if bash "$SCRIPT" "$fake_disk" >/dev/null 2>&1; then
  echo 'FAIL: duplicate identical init= options were accepted' >&2
  ((adversarial_failures += 1))
fi
mv "$work/good-entry-duplicate" "$root/boot/loader/entries/nixos-test.conf"

reset_efi
printf 'stale kernel\n' >"$root/boot/EFI/nixos/kernel.efi"
if bash "$SCRIPT" "$fake_disk" >/dev/null 2>&1; then
  echo 'FAIL: loader entry with a stale kernel was accepted' >&2
  exit 1
fi
cp "$root/nix/store/11111111111111111111111111111111-test-kernel/bzImage" "$root/boot/EFI/nixos/kernel.efi"

reset_efi
printf 'stale initrd\n' >"$root/boot/EFI/nixos/initrd.efi"
if bash "$SCRIPT" "$fake_disk" >/dev/null 2>&1; then
  echo 'FAIL: loader entry with a stale initrd was accepted' >&2
  exit 1
fi
cp "$root/nix/store/22222222222222222222222222222222-test-initrd/initrd" "$root/boot/EFI/nixos/initrd.efi"

reset_efi
cp "$root/boot/loader/entries/nixos-test.conf" "$work/good-entry"
printf '%s\n' \
  'title NixOS test' \
  'linux /EFI/nixos/kernel.efi' \
  'initrd /EFI/nixos/initrd.efi' \
  'options init=/nix/store/33333333333333333333333333333333-wrong-system/init quiet' \
  >"$root/boot/loader/entries/nixos-test.conf"
if bash "$SCRIPT" "$fake_disk" >/dev/null 2>&1; then
  echo 'FAIL: loader entry with the wrong init was accepted' >&2
  exit 1
fi
mv "$work/good-entry" "$root/boot/loader/entries/nixos-test.conf"

reset_efi
FINDMNT_FSTYPE=ext4
export FINDMNT_FSTYPE
if bash "$SCRIPT" "$fake_disk" >/dev/null 2>&1; then
  echo 'FAIL: non-vfat boot mount was accepted as the ESP' >&2
  exit 1
fi

reset_efi
FINDMNT_SOURCE="$work/not-the-esp"
export FINDMNT_SOURCE
if bash "$SCRIPT" "$fake_disk" >/dev/null 2>&1; then
  echo 'FAIL: mismatched /mnt/boot source was accepted' >&2
  exit 1
fi

reset_efi
printf 'default missing.conf\n' >"$root/boot/loader/loader.conf"
if bash "$SCRIPT" "$fake_disk" >/dev/null 2>&1; then
  echo 'FAIL: nonexistent loader default was accepted' >&2
  exit 1
fi
printf 'default nixos-test.conf\n' >"$root/boot/loader/loader.conf"

reset_efi
saved_partuuid=$PARTUUID
PARTUUID=''
export PARTUUID
if bash "$SCRIPT" "$fake_disk" >/dev/null 2>&1; then
  echo 'FAIL: ESP without a PARTUUID was accepted' >&2
  exit 1
fi
PARTUUID=$saved_partuuid
export PARTUUID

reset_efi
IGNORE_CREATE=1
export IGNORE_CREATE
if bash "$SCRIPT" "$fake_disk" >/dev/null 2>&1; then
  echo 'FAIL: failed NVRAM entry creation was accepted' >&2
  exit 1
fi

reset_efi
IGNORE_BOOTORDER=1
export IGNORE_BOOTORDER
if bash "$SCRIPT" "$fake_disk" >/dev/null 2>&1; then
  echo 'FAIL: ignored BootOrder update was accepted' >&2
  exit 1
fi

((adversarial_failures == 0)) || exit 1

echo 'installed boot verification regressions: PASS'
