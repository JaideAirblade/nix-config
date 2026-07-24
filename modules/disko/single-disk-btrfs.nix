# Standard single-disk UEFI layout (btrfs root with subvolumes + FAT32 ESP).
# Used by hosts that want btrfs subvolumes for snapshots, deduplication, etc.
#
# Import this in hosts/<name>/disk-layout.nix and set:
#   disko.devices.disk.main.device = "/dev/sda";
#
# Layout:
#   - 1G   EFI System Partition (ESP, FAT32, /boot)
#   - rest btrfs with subvolumes:
#       @       → /        (root)
#       @nix    → /nix     (nix store)
#       @home   → /home    (user data)
#       @var    → /var     (system state)
#       @snap   → /.snapshots (for snapper/btrbk rollback)
#
# zstd compression is set per-subvolume via mountOptions.
{ lib, ... }:

{
  disko.devices.disk.main = {
    type = "disk";
    # device = "/dev/sda";  # SET PER-HOST

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

        # Root — rest of disk, btrfs with subvolumes
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes = {
              "@" = {
                mountpoint = "/";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
              "@/nix" = {
                mountpoint = "/nix";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
              "@/home" = {
                mountpoint = "/home";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
              "@/var" = {
                mountpoint = "/var";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
              "@/snapshots" = {
                mountpoint = "/.snapshots";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
            };
          };
        };
      };
    };
  };
}