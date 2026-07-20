# Graphical file managers + the services Nautilus needs to actually
# see removable media and network shares. Installing the nautilus
# package alone is not enough — it relies on udisks2 for USB/SD cards
# and gvfs for network backends (sftp://, smb://, ftp://, etc.) plus
# trash and MTP. devmon auto-mounts removable drives on insert.
#
# Trash tab fix: NixOS's system-path.nix assembles /run/current-system/sw
# via buildEnv with a WHITELIST of subdirs to link (environment.pathsToLink).
# /share/gvfs is NOT in that whitelist, so gvfs's share/gvfs/mounts/*.mount
# files (including trash.mount) never land in the profile — Nautilus can't
# find the trash backend and the trash tab silently fails. Adding
# /share/gvfs to pathsToLink fixes it.
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    nautilus   # GNOME Files
    file-roller  # Archive Manager — Nautilus "Extract here"/"Compress" UI
    # Backend tools file-roller shells out to for each format:
    zip unzip     # .zip
    p7zip         # .7z (also covers some .zip edge cases)
    unrar-free    # .rar (free implementation; no non-free unrar in nixpkgs)
    xz bzip2 gzip # .tar.xz / .tar.bz2 / .tar.gz
  ];

  # Link gvfs's mount definitions (trash.mount, network.mount, etc.) into
  # /run/current-system/sw/share/gvfs/ so Nautilus can find the backends.
  # See the module header for the full explanation.
  environment.pathsToLink = [ "/share/gvfs" ];

  # USB / removable media detection + auto-mount.
  services.udisks2.enable = true;
  services.devmon.enable = true;

  # GNOME virtual filesystem: network shares, trash, MTP devices, etc.
  services.gvfs.enable = true;
}