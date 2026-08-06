# Disk layout — disko, applied by nixos-anywhere during provisioning and
# by `disko -m format,mount` for in-place changes once NixOS is installed.
#
# Explicitly imported by `hosts/UwU-Server/default.nix`; do not delete this
# file or the import without also removing the disko.devices.* declarations,
# or the system will lose its root filesystem on next rebuild.
#
# Drive inventory (as of 2026-08-06):
#   - nvme1n1  Crucial E100 931GB      → root pool (btrfs with @, @/nix,
#                                       @/home, @/var, @/snapshots + 1G ESP)
#   - nvme0n1  Lexar NM790 3.7TB       → data-media pool (single btrfs @,
#                                       mounted at /media, label data-media)
#   - nvme2n1  Lexar NM790 3.7TB       → data-backup pool (single btrfs @,
#                                       mounted at /backup, label data-backup)
#
# Each data pool is an INDEPENDENT single-device btrfs filesystem. They are
# NOT joined into a multi-device pool (no RAID0/RAID1 across the two Lexars).
# Reason: data-media (Pleias panel, drone footage, seanime library) and
# data-backup (uwu desktop → server backup target) have isolated failure
# domains — losing one Lexar must not take out the other.
#
# IMPORTANT — adding more data drives later:
#   - Each new drive gets its own `disko.devices.disk.<name>` block.
#   - NEVER extend a pool across multiple drives (no `btrfs device add`).
#   - Reference drives by `/dev/disk/by-id/<model>_<serial>` so PCI bus
#     renumbering doesn't break the link.
#
# Format-mode safety contract (enforced by tests/data-pool-layout-regressions.py):
#   1. `nvme1n1` is the ONLY drive referenced for the root pool. A future
#      edit must never add a second reference to `nvme1n1` anywhere in
#      this file, or the format step will wipe the OS drive.
#   2. Each data disk declares `destroy = false` — the `destroy` stage
#      of disko will not touch that disk. `format` skips `mkfs.btrfs` when
#      a btrfs signature is already present (see disko lib/types/btrfs.nix
#      `_create`: the `blkid TYPE=` check is the "skip if exists" gate).
#   3. `extraArgs = []` on every data btrfs — no `-f` flag, no force-overwrite.
#   4. Each data partition uses `size = "100%FREE"` — no chance of disko
#      deciding to shrink an existing partition.
#   5. `mountOptions` of each data pool's `@` subvolume includes
#      `"nofail"` — generated fstab entry has `nofail`, so a missing
#      data drive does not block boot.
#
# NOTE (2026-08-03): when the 2x Maxio MAP1602 4TB NVMes were first seen
# they trained at Gen1 x1 and dropped off the bus (pciehp Slot(0): Link Down).
# The current Lexar NM790 4TBs are stable on the bus per `journalctl -k
# -g nvme` (last drop: 2026-08-05 22:45, recovered by 22:45:15). A future
# 1TB ZFS-labelled NVMe from uwu is planned to join as a third pool.
{
  nixos.hosts."UwU-Server" =
    _:
    {
      # Force-load the NVMe driver in the initrd instead of relying on udev
      # modalias coldplug. The Crucial E100 sits behind a quirky bridge on
      # this board (c1:00.0); without an early force-load the device can lose
      # the race against initrd device discovery → "switch root target
      # contains no usable init". Keep this OUTSIDE hardware-configuration.nix
      # — nixos-generate-config regenerations must not drop it.
      boot.initrd.kernelModules = [ "nvme" ];

      # ── ROOT POOL — Crucial E100 931GB ───────────────────────────
      # THIS is the OS drive. Do NOT change `device` without also
      # updating tests/data-pool-layout-regressions.py — the test
      # asserts `nvme1n1` is referenced exactly once in this file.
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
                extraArgs = [ "-f" ]; # OS drive: force-overwrite is required
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

      # ── DATA-MEDIA POOL — Lexar NM790 3.7TB (nvme0n1) ───────────
      # Mounted at /media. Bulk storage for media library, drone
      # footage, Pleias panel data, etc. Independent btrfs pool.
      disko.devices.disk.dataMedia = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-Lexar_SSD_NM790_4TB_QGW076R008780P2202";
        # DO NOT change `destroy = false` to true without re-reading
        # the "Format-mode safety contract" comment at the top of this
        # file. With `destroy = false`, the disko `destroy` stage is
        # a strict no-op for this disk; `format` skips `mkfs.btrfs`
        # when a btrfs signature is already present.
        destroy = false;
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%FREE";
              content = {
                type = "btrfs";
                # IMPORTANT: no `-f` here. If a future edit adds
                # `extraArgs = [ "-f" ]` it will force-overwrite any
                # existing btrfs on this disk, even if the partition
                # boundary is right. tests/data-pool-layout-regressions.py
                # asserts extraArgs is `[]` on every data disk.
                extraArgs = [ ];
                mountOptions = [ "compress=zstd" "noatime" ];
                subvolumes = {
                  "@" = {
                    mountpoint = "/media";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                      "nofail" # boot must not block on a missing data drive
                    ];
                  };
                };
              };
            };
          };
        };
      };

      # ── DATA-BACKUP POOL — Lexar NM790 3.7TB (nvme2n1) ──────────
      # Mounted at /backup. Backup target for the uwu desktop.
      # Independent btrfs pool — never joined with dataMedia.
      disko.devices.disk.dataBackup = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-Lexar_SSD_NM790_4TB_QGW076R008817P2202";
        destroy = false;
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%FREE";
              content = {
                type = "btrfs";
                extraArgs = [ ];
                mountOptions = [ "compress=zstd" "noatime" ];
                subvolumes = {
                  "@" = {
                    mountpoint = "/backup";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                      "nofail" # boot must not block on a missing data drive
                    ];
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
