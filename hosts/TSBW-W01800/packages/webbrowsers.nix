# Web browsers
{ lib, pkgs, ... }: {
  # Firefox is enabled by the shared modules/packages/packages.nix.

  # Flatpak — for Orion Browser (Kagi), not in nixpkgs for Linux
  services.flatpak.enable = true;
  xdg.portal.enable = true;

  # Flatpak exports .desktop files to /var/lib/flatpak/exports/share
  # but NixOS doesn't add it to XDG_DATA_DIRS by default, so app launchers
  # can't see Flatpak apps. Prepend it without clobbering existing entries.
  environment.sessionVariables.XDG_DATA_DIRS = lib.mkBefore [
    "/var/lib/flatpak/exports/share"
  ];

  # Declarative Flatpak management
  # Orion is a bundle download (not on Flathub), but needs the GNOME runtime from Flathub.
  # NekoPlay (anime video player, fork of Cine) is also a bundle download from GitHub releases.
  # Both .flatpak bundles are fetched deterministically via fetchurl with fixed hashes.
  #
  # system.activationScripts runs as root — needed for system flatpak installs.
  # userActivationScripts runs as the user but can't do system-level flatpak ops.
  system.activationScripts.flatpakManagement = {
    text = let
      grep = pkgs.gnugrep;
      flatpak = pkgs.flatpak;
      orionBundle = pkgs.fetchurl {
        url = "https://orionbrowser.com/download/oriongtk.0.3.0.flatpak";
        hash = "sha256-0NOWPS2Yv5NpnTxqsiMvshHFyTyDotPi964/2og/bCw=";
      };
      nekoPlayBundle = pkgs.fetchurl {
        url = "https://github.com/NyarchLinux/NekoPlay/releases/download/v1.1.1/nekoplay.flatpak";
        hash = "sha256-wU255bPkTdPfKV8KV3FbUymYutePI430inn+R43qRfQ=";
      };
      desiredFlathubApps = [
        "org.gnome.Platform/x86_64/49"
      ];
      desiredApps = "com.kagi.OrionGtk moe.nyarchlinux.nekoplay ${toString desiredFlathubApps}";
    in ''
      export PATH=${flatpak}/bin:$PATH

      # 1. Ensure Flathub remote exists
      flatpak remote-add --if-not-exists flathub \
        https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true

      # 2. Install runtime dependencies from Flathub
      for app in ${toString desiredFlathubApps}; do
        flatpak install -y --noninteractive flathub "$app" 2>/dev/null || true
      done

      # 3. Install Orion from local bundle (fetched via nix fetchurl)
      flatpak install -y --noninteractive ${orionBundle} 2>/dev/null || true

      # 3b. Install NekoPlay from local bundle (fetched via nix fetchurl)
      flatpak install -y --noninteractive ${nekoPlayBundle} 2>/dev/null || true

      # 4. Remove any Flatpaks NOT in our desired list
      installedApps=$(flatpak list --app --columns=application 2>/dev/null)
      for installed in $installedApps; do
        if ! echo "${desiredApps}" | ${grep}/bin/grep -q "$installed"; then
          flatpak uninstall -y --noninteractive "$installed" 2>/dev/null || true
        fi
      done

      # 5. Clean up unused deps
      flatpak uninstall --unused -y 2>/dev/null || true

      # 6. Update everything
      flatpak update -y 2>/dev/null || true
    '';
  };
}