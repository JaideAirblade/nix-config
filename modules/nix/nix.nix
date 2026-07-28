# Nix / nixpkgs settings: flakes, unfree, editor.
_:
{
  nixos.modules.common =
    { lib, ... }:

    {
      # mkDefault so a host can override (e.g. a minimal server that wants
      # unfree disabled) without needing mkForce.
      nixpkgs.config.allowUnfree = lib.mkDefault true;

      nix.settings.experimental-features = [ "nix-command" "flakes" ];

      # We're fully on Flakes — no nix-channel. Disabling removes the channel
      # tools/config so nothing accidentally drifts the system off the flake.lock.
      nix.channel.enable = false;

      # Avoid pulling every package's optional HTML documentation output into
      # the system closure. In the pinned nixpkgs revision, Python 3.12's docs
      # also fail to build with the Python 3.14 Sphinx/docutils toolchain.
      # Man pages, Info pages, and the NixOS manual remain enabled.
      documentation.doc.enable = false;

      environment.variables.EDITOR = "vim";
    }
  ;
}
