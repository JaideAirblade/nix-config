# UwU-Server host-specific packages.
#
# A small list of GUI apps jaide wants when she uses this machine remotely
# (e.g. during the trip to the parents'). The rest of the package set
# comes from the shared modules imported by the entry point.
#
# The box is headless — no display server, no DM. The GUI binaries are
# available so they can be invoked via X-forwarding, `nix run`, or a remote
# desktop session if one is ever set up. They don't auto-start because
# nothing in the desktop session depends on them.

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

        # Readest — modern ebook reader. Same as on UwU.
        readest

        # OfficeCLI — Office suite for AI agents (.docx/.xlsx/.pptx via CLI).
        # Single .NET binary, autoPatchelf'd for NixOS. Skill auto-installed
        # at ~/.hermes/skills/officecli/ by the upstream install script.
        officecli
      ];

      # Opt out of the shared Firefox enable (modules/packages/packages.nix).
      # UwU-Server uses Helium as its primary browser; no second browser.
      programs.firefox.enable = lib.mkForce false;
    }
  ;
}
