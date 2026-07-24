# System-wide packages and environment for TSBW-W01800.
#
# Builds on the shared modules/packages/packages.nix (vim, wget, git,
# just, ripgrep, jq, fzf, ghostty, ...) — this file adds work-specific
# tools (YubiKey, remmina, octarine, masterpdfeditor, ...). Custom
# packages (betterbird, octarine) come from the pkgs/ overlay declared
# in flake.nix.
{ pkgs, lib, ... }:

{
  environment = {
    systemPackages = with pkgs; [
      # Terminals (beyond the shared ghostty)
      kitty

      # System info
      fastfetch
      nvtopPackages.amd  # GPU/process monitor for AMD GPUs

      # YubiKey / FIDO2
      pam_u2f          # provides pamu2fcfg — enroll keys for PAM login/sudo
      yubikey-manager  # provides ykman — manage YubiKey config (USB/OTP/FIDO2)

      # Remote desktop
      remmina           # GTK remote desktop client (RDP, VNC, SSH, etc.)

      # File managers — superfile (TUI, default) + Nautilus (GUI fallback
      # for SMB/network shares that superfile can't browse). Superfile has
      # no upstream .desktop so we wrap it in ghostty for app launchers.
      superfile
      nautilus
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

      # Note-taking & reading
      octarine         # Private markdown note-taking app (custom package from pkgs/)
      readest          # Modern ebook reader (epub, pdf, mobi, cbz, etc.)

      # Cloud sync
      rclone           # Universal cloud storage sync (Google Drive, etc.)

      # USB & media utilities
      gnome-multi-writer  # Write ISO images to multiple USB drives at once (GNOME)
      impression          # Modern GNOME bootable USB writer
      simple-scan         # GNOME scanning utility (requires hardware.sane)

      # Disc burning
      brasero             # GNOME CD/DVD burner

      # PDF editing
      masterpdfeditor4    # Visual PDF editor — text, images, OCR, forms (free, no watermark)

      # 1Password — the NixOS modules (programs._1password / programs._1password-gui)
      # are imported via the shared modules/packages/onepassword module.  We only
      # add the beta GUI package here as the host-specific choice.
      _1password-gui-beta

      # Hermes Agent — installed via the shared modules/ai module's overlay,
      # but the work host also wants the CLI on PATH.
      hermes-agent

      # Zed editor — previously installed via home-manager on this host.
      # FHS-wrapped for extension compatibility.
      zed-editor-fhs
    ];
    variables.EDITOR = "vim";
  };

  # Superfile is the default file manager for directory MIME types.
  # The shared file-manager module also writes this, but TSBW-W01800
  # doesn't import that module, so set it here too.
  environment.etc."xdg/mimeapps.list".text = ''
    [Default Applications]
    inode/directory=superfile.desktop
  '';
}