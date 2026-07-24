# UwU host-specific user overrides.
#
# Adds UwU-only groups (wireshark for packet capture without sudo, plus
# the shared module's defaults: networkmanager, wheel). The macrotool
# and devices modules append input/uinput/plugdev via their own
# users.users."jaide".extraGroups entries, which merge with this list.
#
# NOTE: Do NOT use lib.mkForce on extraGroups — it would override the
# merge and drop the input/uinput groups added by macrotool.nix, breaking
# evdev input capture and uinput injection.
{ lib, ... }:

{
  users.users."jaide" = {
    description = lib.mkForce "Jaide";
    extraGroups = [ "networkmanager" "wheel" "wireshark" "_lldpd" ];
  };
}