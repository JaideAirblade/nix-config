# Mango compositor.
#
# Mango is a Wayland compositor based on dwl. We enable it via its
# NixOS module from the flake. Login is handled by DankGreeter (see
# ../dms/default.nix), which lists mango as a supported compositor and
# runs it under greetd.
{ inputs, ... }:

{
  imports = [ inputs.mangowm.nixosModules.mango ];

  programs.mango.enable = true;
}