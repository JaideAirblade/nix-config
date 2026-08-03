# Mango compositor.
#
# Mango is a Wayland compositor based on dwl. Its NixOS module now ships in
# nixpkgs, so importing the module from the Mango flake would declare the
# `programs.mango` options a second time. Login is handled by DankGreeter (see
# ../dms/default.nix), which lists mango as a supported compositor and
# runs it under greetd.
_:
{
  nixos.modules.common =
    _:

    {
      programs.mango.enable = true;
    }
  ;
}
