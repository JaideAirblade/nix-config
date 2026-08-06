# UwU-Server host-specific packages.
#
# Currently a small list of GUI apps jaide wants when she uses this machine
# remotely (e.g. during the trip to the parents'). The rest of the package
# set comes from the shared modules imported by the entry point.

_:
{
  nixos.hosts."UwU-Server" =
    { pkgs, lib, ... }:

    {
      environment.systemPackages = with pkgs; [
        # Helium — private Chromium-based browser. Matches the desktop
        # experience on UwU/TSBW so the 1Password integration, profile, and
        # extensions are consistent across machines.
        helium-bin
      ];

      # Opt out of the shared Firefox enable (modules/packages/packages.nix).
      # UwU-Server uses Helium as its primary browser; no second browser.
      programs.firefox.enable = lib.mkForce false;
    }
  ;
}
