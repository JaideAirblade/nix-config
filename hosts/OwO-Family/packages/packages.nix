# Host-specific packages for OwO-Family.
# Same base as UwU's packages.nix but without gaming apps (Discord, Seanime,
# Chromium, Geary, Hytale, etc.) — this is a family PC, not Jaide's desktop.
_:
{
  nixos.hosts."OwO-Family" =
    { pkgs, ... }:

    {
      environment.systemPackages = with pkgs; [
        # Basic USB tooling
        usbutils

        # Firefox — web browser
        firefox

        # Readest is provided by modules/theming/readest-dms-theme.nix as a
        # wrapped version with WEBKIT_INSPECTOR_HTTP_SERVER=127.0.0.1:9223

        # Octarine — notes (custom package from overlay)
        octarine
      ];
    }
  ;
}
