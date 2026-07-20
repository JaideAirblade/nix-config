# UwU host-specific packages.
#
# Imports the shared packages subfolders (file-manager, onepassword,
# network-tools, media) that UwU wants, and adds UwU-only GUI apps that
# the work host doesn't need (Discord+Equicord, Seanime, Geary, Chromium
# for WebHID, etc.).
{ pkgs, lib, ... }:

{
  imports = [
    # Shared subfolder modules — these live under modules/packages/ and
    # are opt-in per host.
    ../../../modules/packages/file-manager
    ../../../modules/packages/onepassword
    ../../../modules/packages/network-tools
    ../../../modules/packages/media
  ];

  environment.systemPackages = with pkgs; [
    # IVPN UI desktop entry override — force X11 + --disable-gpu.
    # The stock ivpn-ui wrapper honours NIXOS_OZONE_WL=1 (set globally in
    # theming.nix) and adds --ozone-platform-hint=auto, which makes Electron
    # try native Wayland. On MangoWM that crashes with a Vulkan/Wayland
    # incompatibility, killing the UI (including the close/disconnect dialog).
    # hiPrio shadows the upstream .desktop file so app launchers pick this one.
    (lib.hiPrio (makeDesktopItem {
      name = "ivpn-ui";
      desktopName = "IVPN";
      genericName = "VPN Client";
      comment = "UI interface for IVPN";
      icon = "ivpn-ui";
      categories = [ "Network" ];
      exec = "ivpn-ui --ozone-platform=x11 --disable-gpu";
      startupNotify = true;
    }))
    # Discord with Equicord (client mod — plugins, custom CSS, etc.)
    # withEquicord patches the stock Discord client via the equicord package.
    (discord.override { withEquicord = true; })

    # Readest — modern ebook reader.
    readest

    # Basic USB tooling — lsusb and friends. Without this you can't even
    # identify what's plugged in from the CLI.
    usbutils

    # Secondary Chromium-based browser. Needed for WebHID device configuration
    # (Scyrox web configurator at scyrox.net) — Firefox doesn't support WebHID.
    # Also a reasonable fallback for sites that break under your main browser
    # or your Equicord-patched Discord setup.
    chromium

    # Seanime — self-hosted anime/manga media server (desktop app + web UI).
    seanime

    # Octarine — private markdown note-taking app (custom package from pkgs/).
    octarine

    # Zed — GPU-accelerated collaborative code editor.
    zed-editor

    # Geary — GTK email client. Follows libadwinda/GNOME theming, fits the
    # standalone-WM + adw-gtk3-dark setup without pulling all of GNOME.
    geary

    # Hytale Launcher — official launcher for Hytale (custom package from pkgs/).
    # Wrapped in buildFHSEnv so the pre-built binary finds its libraries.
    hytale
  ];
}