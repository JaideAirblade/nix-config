# UwU host-specific packages.
#
# Imports the shared packages subfolders (file-manager, onepassword,
# network-tools, media) that UwU wants, and adds UwU-only GUI apps that
# the work host doesn't need (Discord+Equicord, Seanime, Geary, Chromium
# for WebHID, etc.).
{ pkgs, ... }:

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

    # Geary — GTK email client. Follows libadwaita/GNOME theming, fits the
    # standalone-WM + adw-gtk3-dark setup without pulling all of GNOME.
    geary
  ];
}