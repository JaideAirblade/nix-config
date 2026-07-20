# Flatpak — for apps not available in nixpkgs (Sober/Roblox, Twintail
# Launcher, etc.)
#
# Sober is a closed-source Roblox client distributed only via Flathub.
# Twintail Launcher is an open-source anime game launcher (Genshin
# Impact, Honkai Star Rail, ZZZ, Wuthering Waves, etc.) also on Flathub.
# Neither has a nixpkgs package. We enable Flatpak and declaratively
# install both via an activation script (same pattern as TSBW-W01800's
# webbrowsers.nix for Orion/NekoPlay).
#
# Sober requires a working GPU + 3D acceleration (already provided by the
# NVIDIA driver in graphics.nix). The Flatpak runtime handles the rest.
#
# Manual: after deploying, run Sober from your app launcher. It will
# prompt to install Roblox on first launch.
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

  # Declarative Flatpak management — ensures Sober is installed and
  # removes anything not in the desired list. Runs as root via
  # system.activationScripts (same pattern as TSBW-W01800).
  system.activationScripts.flatpakManagement = {
    text = let
      grep = pkgs.gnugrep;
      flatpak = pkgs.flatpak;
      desiredFlathubApps = [
        "org.vinegarhq.Sober"
        "app.twintaillauncher.ttl"
      ];
      desiredApps = builtins.concatStringsSep " " desiredFlathubApps;
    in ''
      export PATH=${flatpak}/bin:$PATH

      # 1. Ensure Flathub remote exists
      flatpak remote-add --if-not-exists flathub \
        https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true

      # 2. Install desired apps from Flathub
      for app in ${desiredApps}; do
        flatpak install -y --noninteractive flathub "$app" 2>/dev/null || true
      done

      # 3. Remove any Flatpaks NOT in our desired list
      installedApps=$(flatpak list --app --columns=application 2>/dev/null)
      for installed in $installedApps; do
        if ! echo "${desiredApps}" | ${grep}/bin/grep -q "$installed"; then
          flatpak uninstall -y --noninteractive "$installed" 2>/dev/null || true
        fi
      done

      # 4. Clean up unused deps
      flatpak uninstall --unused -y 2>/dev/null || true

      # 5. Update everything
      flatpak update -y 2>/dev/null || true
    '';
  };
}