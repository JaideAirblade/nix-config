# UwU host-specific packages.
#
# Imports the shared packages subfolders (file-manager, onepassword,
# network-tools, media) that UwU wants, and adds UwU-only GUI apps that
# the work host doesn't need (Discord+Equicord, Seanime, Geary, Chromium
# for WebHID, etc.).
{ pkgs, lib, ... }:

{
  # Shared package modules (file-manager, onepassword, network-tools,
  # osint, media) are imported by the host entry point (default.nix)
  # via config.nixosModules.packages-* — not via imports here.

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

    # Discord — force XWayland via desktop entry override.
    # NIXOS_OZONE_WL=1 (set globally in theming.nix) makes Electron apps
    # try native Wayland. On NVIDIA + MangoWM, Discord flickers badly in
    # native Wayland mode (libEGL dri2 screen failures + compositor
    # re-allocation on every frame). XWayland is stable. hiPrio shadows
    # the upstream .desktop file.
    (lib.hiPrio (makeDesktopItem {
      name = "discord";
      desktopName = "Discord";
      genericName = "Internet Messenger";
      comment = "Discord — with Equicord client mod";
      icon = "discord";
      categories = [ "Network" "InstantMessaging" ];
      exec = "discord --ozone-platform=x11";
      startupNotify = true;
      mimeTypes = [ "x-scheme-handler/discord" ];
    }))

    # Discord with Equicord (client mod — plugins, custom CSS, etc.)
    # withEquicord patches the stock Discord client via the equicord package.
    (discord.override { withEquicord = true; })

    # Readest — modern ebook reader.
    readest

    # Calibre — ebook management. Used with ACSM Input + DeDRM plugins
    # to download EPUBs from Google Play Books (ACSM → DRM-free EPUB).
    calibre

    # Basic USB tooling — lsusb and friends. Without this you can't even
    # identify what's plugged in from the CLI.
    usbutils

    # Chromium — force XWayland via desktop entry overrides.
    # NIXOS_OZONE_WL=1 (set globally in theming.nix) makes Chromium try native
    # Wayland, which on NVIDIA + MangoWM flickers and produces visual artifacts
    # (MangoWM issue #1181 — same root cause as the Discord override above).
    # XWayland is stable.
    #
    # We shadow BOTH upstream .desktop files:
    #   chromium.desktop        — used by app launchers
    #   chromium-browser.desktop — used by xdg-mime as the default HTTP handler
    # Without shadowing the second one, links clicked from Discord/other apps
    # launch the unpatched entry → native Wayland → GPU segfaults in
    # libnvidia-eglcore.so → compositor flicker. hiPrio ensures both override.
    (lib.hiPrio (makeDesktopItem {
      name = "chromium";
      desktopName = "Chromium";
      genericName = "Web Browser";
      comment = "Chromium browser (XWayland)";
      icon = "chromium";
      categories = [ "Network" "WebBrowser" ];
      exec = "chromium --ozone-platform=x11";
      startupNotify = true;
      mimeTypes = [
        "x-scheme-handler/http"
        "x-scheme-handler/https"
        "x-scheme-handler/ftp"
        "text/html"
        "text/xml"
        "application/xhtml+xml"
      ];
    }))
    (lib.hiPrio (makeDesktopItem {
      name = "chromium-browser";
      desktopName = "Chromium";
      genericName = "Web Browser";
      comment = "Chromium browser (XWayland)";
      icon = "chromium";
      categories = [ "Network" "WebBrowser" ];
      exec = "chromium --ozone-platform=x11 %U";
      startupNotify = true;
      startupWMClass = "chromium-browser";
      noDisplay = true;
      mimeTypes = [
        "x-scheme-handler/http"
        "x-scheme-handler/https"
        "x-scheme-handler/ftp"
        "text/html"
        "text/xml"
        "application/xhtml+xml"
      ];
    }))

    # The actual chromium binary (the desktop entries above just shadow the
    # upstream .desktop files to add --ozone-platform=x11).
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