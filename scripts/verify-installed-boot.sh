#!/usr/bin/env bash
# Verify an installed NixOS systemd-boot path before allowing remote reboot.
set -euo pipefail

[[ $# -eq 1 ]] || { echo "Usage: verify-installed-boot.sh <whole-disk-by-id>" >&2; exit 2; }
disk=$1
target_root=${TARGET_ROOT:-/mnt}
efivars_path=${EFIVARS_PATH:-/sys/firmware/efi/efivars}
test_mode=${BOOT_VERIFY_TEST_MODE:-0}
loader_path='\EFI\systemd\systemd-bootx64.efi'

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

find_efi_entry() {
  local output=$1
  local wanted_uuid=${2,,}
  local wanted_part=$3
  python3 -c '
import re, sys

uuid, part, loader = sys.argv[1:]
pattern = re.compile(
    r"^Boot([0-9A-Fa-f]{4})\*\s+Linux Boot Manager\s+"
    + r"HD\("
    + re.escape(part)
    + r",GPT,"
    + re.escape(uuid)
    + r",[^,()]+,[^,()]+\)/\\?File\("
    + re.escape(loader)
    + r"\)$",
    re.IGNORECASE,
)
for line in sys.stdin:
    match = pattern.fullmatch(line.rstrip("\r\n"))
    if match:
        print(match.group(1))
        raise SystemExit(0)
raise SystemExit(1)
' "$wanted_uuid" "$wanted_part" "$loader_path" <<<"$output"
}

boot_order_from() {
  local output=$1
  local line order
  while IFS= read -r line; do
    if [[ "$line" == BootOrder:* ]]; then
      order=${line#BootOrder:}
      order=${order//[[:space:]]/}
      [[ -n "$order" ]] || return 1
      printf '%s\n' "$order"
      return 0
    fi
  done <<<"$output"
  return 1
}

is_canonical_store_root() {
  local pattern='^/nix/store/[0123456789abcdfghijklmnpqrsvwxyz]{32}-[A-Za-z0-9+._?=-]+$'
  [[ "$1" =~ $pattern ]]
}

is_canonical_store_artifact() {
  local path=$1
  local pattern='^/nix/store/[0123456789abcdfghijklmnpqrsvwxyz]{32}-[A-Za-z0-9+._?=-]+(/[A-Za-z0-9+._?=-]+)+$'
  local relative component
  local -a components=()
  [[ "$path" =~ $pattern ]] || return 1
  relative=${path#/nix/store/}
  IFS=/ read -ra components <<<"$relative"
  for component in "${components[@]}"; do
    [[ "$component" != . && "$component" != .. ]] || return 1
  done
}

resolve_system_profile() {
  local current="$target_root/nix/var/nix/profiles/system"
  local target
  local _
  for _ in {1..8}; do
    [[ -L "$current" ]] || return 1
    target=$(readlink "$current") || return 1
    if [[ "$target" == /nix/store/* ]]; then
      is_canonical_store_root "$target" || return 1
      printf '%s\n' "$target"
      return 0
    fi
    [[ "$target" =~ ^[A-Za-z0-9._+-]+$ ]] || return 1
    current="$(dirname "$current")/$target"
    [[ "$current" == "$target_root"/* ]] || return 1
  done
  return 1
}

bootspec_values() {
  local file=$1
  python3 -c '
import json, sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        document = json.load(handle)
    bootspec = document["org.nixos.bootspec.v1"]
    if not isinstance(bootspec, dict):
        raise TypeError
    values = [bootspec[name] for name in ("toplevel", "init", "kernel", "initrd")]
    if any(not isinstance(value, str) or not value or "\n" in value or "\r" in value for value in values):
        raise TypeError
except (OSError, UnicodeError, json.JSONDecodeError, KeyError, TypeError):
    raise SystemExit(1)
print(*values, sep="\n")
' "$file"
}

[[ -d "$efivars_path" && -w "$efivars_path" ]] \
  || fail "installer is not booted with writable UEFI variables"
command -v python3 >/dev/null || fail "python3 is required for exact EFI and boot.json parsing"
efi_output=$(efibootmgr -v) || fail "efibootmgr cannot read UEFI variables"

real_disk=$(readlink -f "$disk")
if [[ "$test_mode" != 1 ]]; then
  [[ -b "$real_disk" ]] || fail "target disk is not a block device: $disk"
fi

mount_record=$(findmnt -n -o SOURCE,TARGET,FSTYPE --target "$target_root/boot") \
  || fail "$target_root/boot is not mounted"
read -r esp_source esp_target esp_fstype extra <<<"$mount_record"
[[ -z ${extra:-} && "$esp_target" == "$target_root/boot" && "$esp_fstype" == vfat ]] \
  || fail "$target_root/boot is not an exact vfat mount"
real_esp=$(readlink -f "$esp_source")
if [[ "$test_mode" != 1 ]]; then
  [[ -b "$real_esp" ]] || fail "ESP source is not a block device: $esp_source"
fi
parent_disk=$(lsblk -npo PKNAME "$real_esp")
[[ -n "$parent_disk" && "$(readlink -f "$parent_disk")" == "$real_disk" ]] \
  || fail "$target_root/boot is not mounted from the configured target disk"
part_number=$(lsblk -no PARTN "$real_esp")
[[ "$part_number" =~ ^[1-9][0-9]*$ ]] || fail "cannot determine ESP partition number"
partuuid=$(blkid -s PARTUUID -o value "$real_esp")
[[ -n "$partuuid" ]] || fail "ESP has no PARTUUID"

boot_root="$target_root/boot"
[[ -f "$boot_root/EFI/systemd/systemd-bootx64.efi" ]] \
  || fail "systemd-boot EFI binary is missing"
loader_conf="$boot_root/loader/loader.conf"
[[ -s "$loader_conf" ]] || fail "loader.conf is missing or empty"

preferred_entry=''
default_entry=''
while read -r directive value _; do
  case "$directive" in
    preferred) preferred_entry=$value ;;
    default) default_entry=$value ;;
  esac
done <"$loader_conf"
selected_entry=${preferred_entry:-$default_entry}
[[ "$selected_entry" =~ ^[A-Za-z0-9._+-]+\.conf$ ]] \
  || fail "loader default is missing, wildcarded, or unsafe: ${selected_entry:-<empty>}"
entry_file="$boot_root/loader/entries/$selected_entry"
[[ -f "$entry_file" ]] || fail "selected loader entry does not exist: $selected_entry"

expected_system=$(resolve_system_profile) \
  || fail "installed system profile is missing or unsafe"
boot_json="$target_root$expected_system/boot.json"
[[ -f "$target_root$expected_system/init" && -f "$boot_json" ]] \
  || fail "installed system profile does not point to a usable NixOS system"
boot_values=()
mapfile -t boot_values < <(bootspec_values "$boot_json")
[[ ${#boot_values[@]} -eq 4 ]] \
  || fail "installed system boot.json has no valid org.nixos.bootspec.v1 object"
expected_toplevel=${boot_values[0]}
expected_init=${boot_values[1]}
expected_kernel=${boot_values[2]}
expected_initrd=${boot_values[3]}
is_canonical_store_root "$expected_toplevel" \
  || fail "installed boot.json has a non-canonical toplevel path"
is_canonical_store_artifact "$expected_kernel" \
  || fail "installed boot.json has a non-canonical kernel path"
is_canonical_store_artifact "$expected_initrd" \
  || fail "installed boot.json has a non-canonical initrd path"
[[ "$expected_toplevel" == "$expected_system" \
  && "$expected_init" == "$expected_system/init" \
  && -f "$target_root$expected_kernel" \
  && -f "$target_root$expected_initrd" ]] \
  || fail "installed boot.json does not describe the selected system profile"

linux_count=0
initrd_count=0
init_count=0
while read -r directive remainder; do
  case "$directive" in
    linux)
      ((linux_count += 1))
      [[ "$remainder" == /* && "$remainder" != *..* && -f "$boot_root$remainder" ]] \
        || fail "selected loader entry references a missing kernel"
      cmp -s "$boot_root$remainder" "$target_root$expected_kernel" \
        || fail "selected loader entry does not contain the installed kernel"
      ;;
    initrd)
      ((initrd_count += 1))
      [[ "$remainder" == /* && "$remainder" != *..* && -f "$boot_root$remainder" ]] \
        || fail "selected loader entry references a missing initrd"
      cmp -s "$boot_root$remainder" "$target_root$expected_initrd" \
        || fail "selected loader entry does not contain the installed initrd"
      ;;
    options)
      for option in $remainder; do
        if [[ "$option" == init=* ]]; then
          ((init_count += 1))
          [[ "$option" == "init=${expected_init}" ]] \
            || fail "selected loader entry has a conflicting init= option"
        fi
      done
      ;;
  esac
done <"$entry_file"
((linux_count == 1 && initrd_count == 1 && init_count == 1)) \
  || fail "selected loader entry does not boot the installed generation"

entry=$(find_efi_entry "$efi_output" "$partuuid" "$part_number" || true)
if [[ -z "$entry" ]]; then
  echo "Creating an EFI entry for ESP PARTUUID $partuuid"
  efibootmgr -c -d "$real_disk" -p "$part_number" \
    -L "Linux Boot Manager" -l "$loader_path" >/dev/null
  efi_output=$(efibootmgr -v) || fail "cannot re-read UEFI variables after entry creation"
  entry=$(find_efi_entry "$efi_output" "$partuuid" "$part_number" || true)
fi
[[ -n "$entry" ]] \
  || fail "no NVRAM entry matches both the real ESP and systemd-boot executable"

boot_order=$(boot_order_from "$efi_output") || fail "BootOrder is missing"
new_order=$entry
IFS=, read -ra old_entries <<<"$boot_order"
for old in "${old_entries[@]}"; do
  [[ "${old^^}" == "${entry^^}" || -z "$old" ]] || new_order+=",$old"
done
efibootmgr -o "$new_order" >/dev/null

verified_output=$(efibootmgr -v) || fail "cannot verify BootOrder after update"
verified_entry=$(find_efi_entry "$verified_output" "$partuuid" "$part_number" || true)
[[ "${verified_entry^^}" == "${entry^^}" ]] \
  || fail "the exact systemd-boot NVRAM entry disappeared after update"
verified_order=$(boot_order_from "$verified_output") || fail "BootOrder is missing after update"
[[ "${verified_order%%,*}" == "$entry" ]] \
  || fail "firmware did not place the exact systemd-boot entry first"

echo "Verified selected NixOS generation, ESP $real_esp ($partuuid), NVRAM entry $entry, and BootOrder."
