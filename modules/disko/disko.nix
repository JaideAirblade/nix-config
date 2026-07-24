# Declarative disk partitioning via disko.
#
# This module provides a reusable single-disk UEFI layout. Each host that
# wants disko sets:
#   disko.devices.disk.main.device = "/dev/nvme1n1";
# in its own disk-layout.nix file.
#
# The layout is intentionally simple to match UwU's current setup:
#   - 1G   EFI System Partition (ESP, FAT32, /boot)
#   - rest XFS root (mounts at / and /nix/store since they're the same partition)
#
# No LUKS, no btrfs subvolumes, no swap — keep it simple.
# Add complexity later if a host needs it.
#
# To test the layout in a VM before deploying:
#   nix run github:nix-community/nixos-anywhere -- --flake .#UwU --vm-test
#
# To deploy to a fresh machine:
#   nix run github:nix-community/nixos-anywhere -- --flake .#UwU --target-host root@<ip>
{ lib, ... }:

{
  options.disko = {
    device = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Block device path for the main disk (e.g. /dev/nvme1n1).";
    };
  };

  config = {
    # The actual disk layout is defined per-host in hosts/<name>/disk-layout.nix
    # This module just provides the option + the disko import.
  };
}