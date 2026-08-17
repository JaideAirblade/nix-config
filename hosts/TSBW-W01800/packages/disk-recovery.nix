# Disk health monitoring, BitLocker unlocking, Windows recovery,
# and data recovery tools for rescue / forensics workflows.
_:
{
  nixos.hosts."TSBW-W01800" =
    { pkgs, ... }: {
      environment.systemPackages = with pkgs; [
        # ── Disk health & faulty block detection ──────────────────────
        smartmontools # smartctl / smartd — SMART health for HDD/SSD
        nvme-cli # nvme smart-log / error-log — NVMe health & controller logs
        hdparm # ATA/SATA drive parameters, secure erase, bad-block checks

        # ── BitLocker decryption ──────────────────────────────────────
        dislocker # mount BitLocker-encrypted partitions (password/recovery key)
        libbde # BitLocker Drive Encryption format library & tools

        # ── Windows offline registry / settings editing ───────────────
        chntpw # reset Windows local passwords, enable/disable accounts, edit registry offline
        hivex # hivexget/hivexset/hivexml — read & write Windows registry hives
        regripper # forensic Windows registry extraction & analysis

        # ── NTFS / exFAT filesystem support ───────────────────────────
        ntfs3g # FUSE NTFS driver with full read/write support
        ntfsprogs-plus # ntfsfix, ntfsclone, ntfsresize, ntfsinfo utilities
        exfatprogs # exFAT filesystem utilities (mkfs.exfat, exfatfsck, etc.)

        # ── Data recovery ─────────────────────────────────────────────
        testdisk # partition recovery & repair (also includes photorec)
        ddrescue # rescue data from failing/damaged drives with mapfile
        sleuthkit # forensic toolkit: fls, icat, mmls, fsstat — recover deleted files
        scrounge-ntfs # recover data from corrupted NTFS filesystems
      ];

      # smartd (the daemon) is provided by the shared nixos.modules.maintenance
      # module (modules/maintenance/smartd.nix), which pulls
      # smartmontools as a runtime dep so smartctl is on $PATH.
      # Per-host tuning (battery start/stop) lives in
      # services/battery-services.nix and uses a systemd unit drop-in,
      # not a re-declaration of services.smartd.
    }
  ;
}
