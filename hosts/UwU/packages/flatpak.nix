# Flatpak — for apps not available in nixpkgs (Sober/Roblox, Twintail
# Launcher, etc.)
#
# Sober is a closed-source Roblox client distributed only via Flathub.
# Twintail Launcher is an open-source anime game launcher (Genshin
# Impact, Honkai Star Rail, ZZZ, Wuthering Waves, etc.) also on Flathub.
# Neither has a nixpkgs package. We enable Flatpak and declaratively
# install both from a network-online systemd service.
#
# Sober requires a working GPU + 3D acceleration (already provided by the
# NVIDIA driver in graphics.nix). The Flatpak runtime handles the rest.
#
# Manual: after deploying, run Sober from your app launcher. It will
# prompt to install Roblox on first launch.
_:
{
  nixos.hosts."UwU" =
    { lib, pkgs, ... }:

    {
      services.flatpak.enable = true;
      xdg.portal.enable = true;

      # Flatpak exports .desktop files to /var/lib/flatpak/exports/share but
      # NixOS doesn't add it to XDG_DATA_DIRS by default, so app launchers
      # can't see Flatpak apps. Prepend it without clobbering existing entries.
      environment.sessionVariables.XDG_DATA_DIRS = lib.mkBefore [
        "/var/lib/flatpak/exports/share"
      ];

      # Network operations must not run during NixOS activation: activation
      # has no network guarantee and must not mutate unrelated user apps.
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
            desiredFlathubApps = [
              "org.vinegarhq.Sober"
              "app.twintaillauncher.ttl"
              # NymVPN GUI client; the nym-vpnd daemon is packaged in Nix.
              "net.nymtech.NymVPN"
            ];
            desiredApps = builtins.concatStringsSep " " desiredFlathubApps;
          in
          ''
            export PATH=${flatpak}/bin:$PATH

            # Ensure Flathub and the explicitly managed applications exist.
            flatpak remote-add --if-not-exists flathub \
              https://flathub.org/repo/flathub.flatpakrepo

            for app in ${desiredApps}; do
              flatpak install -y --noninteractive flathub "$app"
            done
          '';
      };
    }
  ;
}
