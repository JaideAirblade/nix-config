# File managers + the services Nautilus needs to actually see removable
# media and network shares. Installing the nautilus package alone is not
# enough — it relies on udisks2 for USB/SD cards and gvfs for network
# backends (sftp://, smb://, ftp://, etc.) plus trash and MTP. devmon
# auto-mounts removable drives on insert.
#
# Superfile is a TUI file manager — it has no .desktop file upstream, so
# we create one that wraps it in ghostty (the system-wide terminal). This
# lets app launchers open directories in superfile, and xdg-mime sets it
# as the default for inode/directory. Nautilus stays installed as a
# fallback for SMB/network shares (superfile is local-fs only).
#
# Trash tab fix: NixOS's system-path.nix assembles /run/current-system/sw
# via buildEnv with a WHITELIST of subdirs to link (environment.pathsToLink).
# /share/gvfs is NOT in that whitelist, so gvfs's share/gvfs/mounts/*.mount
# files (including trash.mount) never land in the profile — Nautilus can't
# find the trash backend and the trash tab silently fails. Adding
# /share/gvfs to pathsToLink fixes it.
{ pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    superfile  # TUI file manager — default for inode/directory
    nautilus   # GNOME Files — fallback for SMB/network shares superfile can't browse
    file-roller  # Archive Manager — Nautilus "Extract here"/"Compress" UI
    # Backend tools file-roller shells out to for each format:
    zip unzip     # .zip
    p7zip         # .7z (also covers some .zip edge cases)
    unrar-free    # .rar (free implementation; no non-free unrar in nixpkgs)
    xz bzip2 gzip # .tar.xz / .tar.bz2 / .tar.gz

    # .desktop entry so app launchers can open directories in superfile.
    # superfile is a TUI app with no upstream .desktop — wrap it in ghostty.
    (makeDesktopItem {
      name = "superfile";
      desktopName = "Superfile";
      genericName = "File Manager";
      comment = "Pretty fancy terminal file manager";
      icon = "system-file-manager";
      categories = [ "System" "FileManager" "Utility" ];
      exec = "ghostty -e superfile";
      startupNotify = true;
      mimeTypes = [ "inode/directory" ];
    })
  ];

  # Superfile is the default file manager for directory MIME types.
  # Write to /etc/xdg/mimeapps.list — xdg-mime reads this as the system
  # default. User overrides go in ~/.config/mimeapps.list (higher priority).
  environment.etc."xdg/mimeapps.list".text = ''
    [Default Applications]
    inode/directory=superfile.desktop
  '';

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