# Declarative disk layout for UwU.
# Samsung 990 PRO 4TB NVMe — btrfs with subvolumes, no encryption.
#
# Used ONLY during the live-ISO reinstall: disko partitions, formats and
# mounts the disk, then nixos-install builds the system from this flake.
#
# IMPORTANT: device uses the stable by-id path, NOT /dev/nvmeXnY —
# NVMe enumeration order is not stable across boots, and this machine
# has a second NVMe drive (GIGABYTE 1TB, holds backup files) that must
# NEVER be formatted.
#
# Layout (from modules/disko/single-disk-btrfs.nix):
#   p1  1G    FAT32  → /boot   (ESP)
#   p2  rest  btrfs  → @ /, @/nix, @/home, @/var, @/snapshots
#                      (compress=zstd, noatime on all subvolumes)
{ ... }:

{
  # Import the shared single-disk btrfs layout (subvolumes + zstd)
  imports = [ ../../modules/disko/single-disk-btrfs.nix ];

  # Samsung 990 PRO 4TB — stable by-id path (see `ls -l /dev/disk/by-id/`)
  disko.devices.disk.main.device = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_with_Heatsink_4TB_S7DSNJ0YC00105E";
}
