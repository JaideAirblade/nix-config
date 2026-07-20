# Bluetooth hardware support.
#
# We enable only the stack (bluez) here — no GUI manager like blueman,
# because DankMaterialShell ships its own bluetooth widget that talks
# to bluez directly via its Services layer. Adding blueman would duplicate
# that and conflict.
{ ... }:

{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
}