# UwU host-specific user overrides.
#
# Adds UwU-only groups (wireshark for packet capture without sudo, plus
# the shared module's defaults: networkmanager, wheel). The macrotool
# and devices modules append input/uinput/plugdev via their own
# users.users."jaide".extraGroups entries, which merge with this list.
{ lib, ... }:

{
  users.users."jaide" = {
    description = lib.mkForce "Jaide";
    extraGroups = lib.mkForce [ "networkmanager" "wheel" "wireshark" ];
  };
}