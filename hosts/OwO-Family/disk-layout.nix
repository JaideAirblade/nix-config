# Declarative disk layout for OwO-Family.
# btrfs with subvolumes + zstd compression + deduplication.
#
# The device path must match the actual disk on the target machine.
# Check with `lsblk` on the target before deploying.
{ ... }:

{
  imports = [ ../../modules/disko/single-disk-btrfs.nix ];

  # Set the actual disk device — CHANGE THIS to match the target's disk
  disko.devices.disk.main.device = "/dev/sda";
}