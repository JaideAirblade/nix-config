# Import-only entry for the wm module set.
#
# Mango (compositor) and DMS (shell + greeter) are shared — both hosts
# use them. Niri is imported by hosts that want it (TSBW-W01800) directly
# from inputs.niri.nixosModules.niri in their host config.
{ ... }:

{
  imports = [
    ./mango
    ./dms
  ];
}