# Gaming stack: Steam (Proton), Heroic Games Launcher, Wine, MangoHud,
# gamescope, vkBasalt, Feral GameMode.
#
# This box has an NVIDIA RTX 3080 (modules/graphics/graphics.nix) running the
# proprietary driver on linuxPackages_latest. Steam + Proton need 32-bit
# graphics drivers, which is why hardware.graphics.enable32Bit is set there
# (added by this module's needs — kept in graphics.nix because it owns the
# graphics driver config and a second `hardware.graphics` block here would
# be a duplicate key).
#
# Wayland note: the session is Wayland (Mango compositor). Steam runs under
# XWayland by default, which works. gamescope gives a native-Wayland
# micro-compositor path for games that benefit from it (res scaling, NIS,
# the Steam Deck "game mode" experience). wineWowPackages.waylandFull is the
# bleeding-edge Wine build with native Wayland support — set DISPLAY unset
# in the wine prefix to actually use it.
{ pkgs, ... }:

{
  # --- Steam + Proton -------------------------------------------------------
  # programs.steam handles the FHS sandbox, 32-bit deps, proton download,
  # and the steam-devices udev rules. Firewall ports are opt-in (we don't
  # open them by default — enable per-use if you use Remote Play / local
  # transfers).
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true; # adds the "gamescope + steam" session
    remotePlay.openFirewall = false;
    dedicatedServer.openFirewall = false;
    localNetworkGameTransfers.openFirewall = false;
  };

  # --- gamescope -----------------------------------------------------------
  # Valve's micro-compositor. capSysNice lets it grab RT scheduling so the
  # game frame pacing is stable even under load.
  programs.gamescope = {
    enable = true;
    capSysNice = true;
  };

  # --- Feral GameMode ------------------------------------------------------
  # Temporary CPU governor/nice/IO priority bumps while a game runs. Picked
  # up automatically by Steam and Heroic when `gamemoderun` is on the launch
  # command.
  programs.gamemode.enable = true;

  # --- Tools / launchers ---------------------------------------------------
  environment.systemPackages = with pkgs; [
    mangohud   # performance overlay (FPS, frametime, CPU/GPU temp) — set MANGOHUD=1
    vkbasalt   # post-processing chain (CAS sharpening, SMAA, etc.) — set VKBASALT=1
    heroic     # Heroic Games Launcher: Epic / GOG / Amazon / SCE games
    itch       # itch.io desktop client — indie game store + launcher

    # Wine — wineWow64Packages.waylandFull is the WoW64 build with native
    # Wayland support (unstable, but the most capable). If a game misbehaves,
    # `wineWow64Packages.staging` is a safer fallback.
    wineWow64Packages.waylandFull
    winetricks

    # steam-run: an FHS bubble for running arbitrary Linux game installers /
    # binaries that assume /lib, /usr/lib, etc. Not needed for Steam itself.
    steam-run

    # ProtonPlus: GUI manager for Wine/Proton compatibility tool versions
    # (GE-Proton, Wine-GE, etc.) — installs them into Steam's compatibilitytools.d
    protonplus

    # Prism Launcher — open-source Minecraft launcher with multi-instance /
    # mod management. Qt-based; runs Java Edition instances with per-instance
    # mods, resource packs, and Java versions.
    prismlauncher

    # --- Native Electron for Electron-based Steam games (FeeBay, etc.) ---
    # Run Windows Electron games natively on Linux by extracting app.asar
    # from the Windows install and launching with the Linux electron binary.
    # On NVIDIA + MangoWM, Electron's native Wayland backend flickers badly
    # (MangoWM issue #1181) — launch with --ozone-platform=x11 to force XWayland.
    electron
  ];
}