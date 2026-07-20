# Disk health monitoring, BitLocker unlocking, Windows recovery,
# and data recovery tools for rescue / forensics workflows.
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # ── Disk health & faulty block detection ──────────────────────
    smartmontools   # smartctl / smartd — SMART health for HDD/SSD
    nvme-cli        # nvme smart-log / error-log — NVMe health & controller logs
    hdparm          # ATA/SATA drive parameters, secure erase, bad-block checks

    # ── BitLocker decryption ──────────────────────────────────────
    dislocker       # mount BitLocker-encrypted partitions (password/recovery key)
    libbde          # BitLocker Drive Encryption format library & tools

    # ── Windows offline registry / settings editing ───────────────
    chntpw          # reset Windows local passwords, enable/disable accounts, edit registry offline
    hivex           # hivexget/hivexset/hivexml — read & write Windows registry hives
    regripper       # forensic Windows registry extraction & analysis

    # ── NTFS / exFAT filesystem support ───────────────────────────
    ntfs3g          # FUSE NTFS driver with full read/write support
    ntfsprogs-plus  # ntfsfix, ntfsclone, ntfsresize, ntfsinfo utilities
    exfatprogs      # exFAT filesystem utilities (mkfs.exfat, exfatfsck, etc.)

    # ── Data recovery ─────────────────────────────────────────────
    testdisk        # partition recovery & repair (also includes photorec)
    ddrescue        # rescue data from failing/damaged drives with mapfile
    sleuthkit       # forensic toolkit: fls, icat, mmls, fsstat — recover deleted files
    scrounge-ntfs   # recover data from corrupted NTFS filesystems
  ];

  # Enable smartd for continuous disk health monitoring
  # (notifications via system journal / smartd mail if configured)
  services.smartd = {
    enable = true;
    autodetect = true;
    # Monitor all autodetected drives: SMART health, errors, temperature warnings
    defaults.autodetected = "-a -o on -S on -n standby -W 4,35,40";
    # Send wall notifications to all users on SMART failures
    notifications.wall.enable = true;
  };
}