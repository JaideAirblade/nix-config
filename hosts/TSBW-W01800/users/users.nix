# TSBW-W01800 host-specific user overrides.
#
# The work laptop uses "Simon" as the description (matches the original
# work config). Groups match the shared defaults (networkmanager, wheel).
{ lib, pkgs, ... }:

{
  users.users."jaide" = {
    description = lib.mkForce "Simon";
    extraGroups = lib.mkForce [ "networkmanager" "wheel" "wireshark" "_lldpd" ];
    packages = with pkgs; [
      kdePackages.kate
    ];
  };
}