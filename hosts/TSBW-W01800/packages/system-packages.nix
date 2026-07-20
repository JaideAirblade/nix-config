# System-wide packages and environment for TSBW-W01800.
#
# Builds on the shared modules/packages/packages.nix (vim, wget, git,
# just, ripgrep, jq, fzf, ghostty, ...) — this file adds work-specific
# tools (YubiKey, remmina, octarine, masterpdfeditor, ...). Custom
# packages (betterbird, octarine) come from the pkgs/ overlay declared
# in flake.nix.
{pkgs, ...}: {
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

      # File manager (Nautilus — uses gvfs from services/gvfs.nix)
      nautilus

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

      # 1Password (the shared modules/packages/onepassword is not imported
      # by this host — we pull it in here instead so the work host gets it
      # without importing the whole UwU-style subfolder tree).
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

  # 1Password — enable the NixOS modules so browser native-messaging hosts
  # are auto-wired and polkit policy is installed for system-auth unlock.
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "jaide" ];
  };
}