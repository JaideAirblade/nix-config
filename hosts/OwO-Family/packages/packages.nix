# Host-specific packages for OwO-Family.
# Same base as UwU's packages.nix but without gaming apps (Discord, Seanime,
# Chromium, Geary, Hytale, etc.) — this is a family PC, not Jaide's desktop.
{ pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    # Basic USB tooling
    usbutils

    # Firefox — web browser
    firefox

    # Readest — ebook reader (Jaide's library syncs)
    readest

    # Octarine — notes (custom package from overlay)
    octarine
  ];
}