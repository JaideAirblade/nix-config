# Import-only entry for the devices module.
# Owns OS-level device access policy: udev rules for HID devices (YubiKey,
# Scyrox keyboard/mouse) and the user groups that grant non-root access.
{ ... }:

{
  imports = [
    ./devices.nix
  ];
}