# Standard single-disk UEFI layout (XFS root + FAT32 ESP).
# Used by hosts that have a single disk with no encryption.
#
# Import this in hosts/<name>/disk-layout.nix and set:
#   disko.devices.disk.main.device = "/dev/nvme1n1";
{ lib, ... }:

{
  disko.devices.disk.main = {
    type = "disk";
    # device = "/dev/nvme1n1";  # SET PER-HOST

    content = {
      type = "gpt";
      partitions = {
        # EFI System Partition — 1G FAT32, mounted at /boot
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "fmask=0077" "dmask=0077" ];
          };
        };

        # Root — rest of disk, XFS, mounted at /
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "xfs";
            mountpoint = "/";
          };
        };
      };
    };
  };
}