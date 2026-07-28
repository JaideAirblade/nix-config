# Web browsers
_:
{
  nixos.hosts."TSBW-W01800" =
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

      # Managed Flatpak installation after networking is online.
      # Orion is a bundle download (not on Flathub), but needs the GNOME runtime from Flathub.
      # NekoPlay (anime video player, fork of Cine) is also a bundle download from GitHub releases.
      # Both .flatpak bundles are fetched deterministically via fetchurl with fixed hashes.
      #
      # Do not perform network I/O, upgrades, or removal of unrelated apps from
      # a NixOS activation script.
      systemd.services.flatpak-management = {
        description = "Install managed system Flatpaks";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          Restart = "on-failure";
          RestartSec = "5min";
        };
        script =
          let
            inherit (pkgs) flatpak;
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
          in
          ''
            export PATH=${flatpak}/bin:$PATH

            # 1. Ensure Flathub remote exists
            flatpak remote-add --if-not-exists flathub \
              https://flathub.org/repo/flathub.flatpakrepo

            # 2. Install runtime dependencies from Flathub
            for app in ${toString desiredFlathubApps}; do
              flatpak install -y --noninteractive flathub "$app"
            done

            # 3. Install Orion from local bundle (fetched via nix fetchurl)
            flatpak install -y --noninteractive ${orionBundle}

            # 3b. Install NekoPlay from local bundle (fetched via nix fetchurl)
            flatpak install -y --noninteractive ${nekoPlayBundle}
          '';
      };
    }
  ;
}
