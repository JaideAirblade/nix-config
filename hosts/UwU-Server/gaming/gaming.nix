# Gaming stack: Steam (Proton), Heroic Games Launcher, Wine, MangoHud,
# gamescope, vkBasalt, Feral GameMode. Mirrors UwU's stack.
#
# GPU is the integrated Radeon 890M (RADV) — Proton and native games work out
# of the box on Mesa; hardware.graphics.enable32Bit lives in
# ../graphics/graphics.nix alongside the driver config.
#
# Wayland note: the session is Wayland (Mango compositor via DankGreeter).
# Steam runs under XWayland by default, which works. gamescope gives a
# native-Wayland micro-compositor path (res scaling, NIS, the Steam Deck
# "game mode" experience).
#
# wineWow64Packages.waylandFull is the WoW64 build with native Wayland
# support; the "full" variant already bundles wine-mono (.NET) and wine-gecko
# (HTML) so prefixes get them without winetricks downloads.
_:
{
  nixos.hosts."UwU-Server" =
    { pkgs, ... }:

    {
      # --- Steam + Proton -------------------------------------------------------
      programs.steam = {
        enable = true;
        # Millennium-wrapped Steam (theme/skin loader), provided by the
        # millennium overlay selected in ./default.nix.
        package = pkgs.millennium-steam;
        gamescopeSession.enable = false; # keep Steam out of DankGreeter's session list
        remotePlay.openFirewall = false;
        dedicatedServer.openFirewall = false;
        localNetworkGameTransfers.openFirewall = false;
      };

      # --- gamescope -----------------------------------------------------------
      # capSysNice lets it grab RT scheduling for stable frame pacing.
      programs.gamescope = {
        enable = true;
        capSysNice = true;
      };

      # --- Feral GameMode ------------------------------------------------------
      programs.gamemode.enable = true;

      # --- Tools / launchers ---------------------------------------------------
      environment.systemPackages = with pkgs; [
        mangohud # performance overlay — set MANGOHUD=1
        mangojuice # GUI editor for MangoHud
        vkbasalt # post-processing chain (CAS sharpening, SMAA) — set VKBASALT=1
        heroic # Heroic Games Launcher: Epic / GOG / Amazon
        itch # itch.io desktop client

        # Wine — see header note; mono + gecko are bundled in this build.
        wineWow64Packages.waylandFull
        winetricks

        # steam-run: FHS bubble for arbitrary Linux game installers/binaries.
        steam-run

        # ProtonPlus: manage GE-Proton / Wine-GE compatibility tools.
        protonplus

        # Prism Launcher — Minecraft with per-instance mods/Java versions.
        prismlauncher
      ];
    }
  ;
}
