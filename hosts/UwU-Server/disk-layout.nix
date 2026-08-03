# Disk layout — disko, applied by nixos-anywhere during provisioning.
#
# Boot/system drive: Crucial E100 1TB (the only NVMe currently visible on the
# bus; see note below). Same btrfs subvolume layout as UwU. Swap is zram
# (modules/boot/boot.nix), so no swap partition.
#
# WARNING: nixos-anywhere reformats this drive. The previous install on it
# was confirmed disposable on 2026-08-03.
#
# NOTE (2026-08-03): the box physically has 3 NVMes installed but two of them
# (Maxio MAP1602-based, PCI 03:00.0 + 04:00.0) trained at Gen1 x1 and fell off
# the bus during boot (pciehp Slot(0): Link Down) — hardware/seating/BIOS
# issue, pending reseat. The final target is 2x1TB + 2x4TB.
#
# ADDING THE DATA DRIVES LATER (once they're back on the bus):
#   Option A (separate btrfs pool, recommended for media/games library):
#     mkfs.btrfs -L data /dev/disk/by-id/<4tb-1> /dev/disk/by-id/<4tb-2>
#     then a fileSystems."/data" entry here (device = "/dev/disk/by-label/data",
#     fsType = "btrfs", options compress=zstd,noatime). Add the 4th drive with
#     `btrfs device add` + `btrfs balance` when it arrives.
#   Option B (grow the root pool): `btrfs device add /dev/... /` + balance —
#     NOT recommended; mixes system and bulk data failure domains.
_:
{
  nixos.hosts."UwU-Server" =
    _:
    {
      disko.devices.disk.main = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-CT1000E100SSD8_2545EAD120AF";
        content = {
          type = "gpt";
          partitions = {
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
  ;
}
