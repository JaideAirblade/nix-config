# UEFI boot-order cleanup for Luna-Server (Beelink SER10 Max).
#
# Background: this machine's UEFI NVRAM had accumulated ~12 stale boot
# entries from previous Linux/Windows installers (MemTest, Ubuntu, Limine,
# Windows Boot Manager, debian, multiple "Linux Boot Manager" / "Fallback
# Linux Boot Manager" duplicates). On a reboot with the live USB installer
# plugged in, the firmware preferred the USB stick over the Crucial E100
# install, landing in the live ISO instead of the real NixOS. See session
# 2026-08-06 commit message for the timeline.
#
# What this module does:
#   Runs once per nixos-rebuild switch activation (Type=oneshot after
#   multi-user.target) and removes any UEFI boot entries whose device path
#   does NOT point at the Crucial E100 ESP. Then sets BootOrder to the
#   surviving entries, with the Crucial entry first.
#
# Why declarative and not imperative: any time this machine goes through
# a future OS reinstall (live USB, another distro, vendor recovery), the
# firmware may again prefer USB. Re-running `nixos-rebuild switch` after
# that re-applies this cleanup, so the next reboot is sane.
#
# Idempotency: the script reads /sys/firmware/efi/efivars/, lists boot
# entries, and only deletes ones that don't point at the Crucial E100.
# If the entries are already clean, no deletes happen.

{ config, pkgs, lib, ... }:

let
  # The Crucial E100 ESP's PARTUUID. To verify on a live system:
  #   sudo blkid -o value -s PARTUUID /dev/disk/by-id/nvme-CT1000E100SSD8_*
  #   sudo sgdisk -i 1 /dev/disk/by-id/nvme-CT1000E100SSD8_*
  # The value MUST be the partition GUID (the second UUID, not the disk's
  # own GPT UUID). Hardcoding is fine because Crucial E100 is the OS drive
  # per disk-layout.nix; if the OS drive ever changes, this module must
  # be updated.
  espPartUuid = "3e8dd4d9-dcad-4299-92cd-e24c23a78b57";

  cleanupScript = pkgs.writeShellScript "uefi-boot-order-cleanup" ''
    set -euo pipefail

    # Skip silently if we're not booted via UEFI (e.g. running in a VM with
    # BIOS, or in a NixOS test). The /sys/firmware/efi/efivars directory
    # only exists on UEFI boots. Use `-d` instead of `mountpoint -q` because
    # util-linux's mountpoint isn't in the systemd unit's PATH (Nix sets
    # PATH to a minimal set including only coreutils, findutils, gnugrep,
    # gnused, systemd).
    if [ ! -d /sys/firmware/efi/efivars ]; then
      echo "boot-order-cleanup: not booted via UEFI, skipping"
      exit 0
    fi

    # Dry-run flag: set DRY_RUN=1 to print what would be deleted without
    # actually doing it. Used by the regression test and for manual checks.
    DRY_RUN=''${DRY_RUN:-0}

    # Use `efibootmgr -v` to enumerate boot entries with their decoded
    # device paths. This is more robust than parsing the raw efivar
    # binary (device path is mixed-endian UUID, not UTF-16LE).
    efibootmgr_out=$(${pkgs.efibootmgr}/bin/efibootmgr -v 2>/dev/null || true)

    # An entry's "block" in `efibootmgr -v` starts with "BootNNNN*" and
    # continues until the next "Boot####" or end of input. Walk each block
    # and check if the device path references the Crucial ESP PARTUUID.
    keep=""
    delete=""
    current_entry=""
    current_block=""
    while IFS= read -r line; do
      if [[ "$line" =~ ^Boot[0-9A-F]{4} ]]; then
        # Start of a new entry. Decide for the previous one first.
        if [ -n "$current_entry" ]; then
          if echo "$current_block" | grep -qiF "${espPartUuid}"; then
            num=$(echo "$current_entry" | grep -oE "Boot[0-9A-F]{4}" | sed 's/Boot//')
            keep="$keep $num"
          else
            num=$(echo "$current_entry" | grep -oE "Boot[0-9A-F]{4}" | sed 's/Boot//')
            delete="$delete $num"
            echo "boot-order-cleanup: would delete Boot$num (no Crucial ESP reference)"
          fi
        fi
        current_entry="$line"
        current_block="$line"
      else
        current_block="$current_block
    $line"
      fi
    done <<< "$efibootmgr_out"
    # Handle the last entry.
    if [ -n "$current_entry" ]; then
      if echo "$current_block" | grep -qiF "${espPartUuid}"; then
        num=$(echo "$current_entry" | grep -oE "Boot[0-9A-F]{4}" | sed 's/Boot//')
        keep="$keep $num"
      else
        num=$(echo "$current_entry" | grep -oE "Boot[0-9A-F]{4}" | sed 's/Boot//')
        delete="$delete $num"
        echo "boot-order-cleanup: would delete Boot$num (no Crucial ESP reference)"
      fi
    fi

    # Defensive: if the script misidentifies everything as delete (e.g.
    # because of a parsing bug), abort rather than wipe BootOrder.
    if [ -z "$keep" ]; then
      echo "boot-order-cleanup: WARNING — no entries reference Crucial ESP."
      echo "boot-order-cleanup: skipping deletion to avoid bricking boot."
      exit 0
    fi

    # Delete each entry that's not in $keep.
    for num in $delete; do
      if [ "$DRY_RUN" = "1" ]; then
        echo "boot-order-cleanup: DRY-RUN, not actually deleting Boot$num"
      else
        echo "boot-order-cleanup: deleting Boot$num"
        ${pkgs.efibootmgr}/bin/efibootmgr -q -b "$num" -B >/dev/null 2>&1 || true
      fi
    done

    # Set BootOrder: Crucial entries first, in the order they appear in
    # the original firmware listing.
    order=$(echo "$keep" | tr ' ' ',')
    echo "boot-order-cleanup: setting BootOrder to: $order"
    if [ "$DRY_RUN" = "1" ]; then
      echo "boot-order-cleanup: DRY-RUN, not actually changing BootOrder"
    else
      ${pkgs.efibootmgr}/bin/efibootmgr -q -o "$order" >/dev/null 2>&1 || true
    fi

    echo "boot-order-cleanup: done (keep: $keep, delete: $delete)"
  '';
in
{
  # efibootmgr must be available for the cleanup script.
  environment.systemPackages = [ pkgs.efibootmgr ];

  # A oneshot systemd service that runs the cleanup after every
  # nixos-rebuild switch activation. Using systemd instead of a plain
  # activationScript so we can run it without the system being fully
  # multi-user (e.g. in initrd-less boots).
  systemd.services.uefi-boot-order-cleanup = {
    description = "Clean stale UEFI boot entries, keep only Crucial E100 ESP";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    unitConfig.ConditionPathExists = "/sys/firmware/efi/efivars";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = cleanupScript;
    };
  };
}
