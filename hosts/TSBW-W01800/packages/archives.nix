# Archive and compression tools
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # GUI archive manager — integrates with Nautilus
    file-roller        # GNOME archive manager (zip, tar, 7z, rar, etc.)

    # CLI compression tools
    zip
    unzip
    p7zip              # 7z, 7za, 7zr
    unrar              # RAR extraction (free unrar)
    xz
    zstd
    bzip2
    gzip
  ];
}