# Declarative disk layout for UwU.
# Samsung 990 PRO 4TB NVMe — single disk, no encryption.
#
# This replaces hardware-configuration.nix's imperative fileSystems entries
# with a declarative disko layout. When deploying via nixos-anywhere,
# disko handles partitioning + formatting automatically.
#
# Current layout (matches existing install):
#   /dev/nvme1n1p1  1G    FAT32  → /boot
#   /dev/nvme1n1p2  3.6T  XFS   → / (root + nix store)
{ ... }:

{
  # Import the shared single-disk XFS layout
  imports = [ ../../modules/disko/single-disk-xfs.nix ];

  # Set the actual disk device for this host
  disko.devices.disk.main.device = "/dev/nvme1n1";
}