# TSBW-W01800 host-specific user overrides.
#
# The work laptop uses "Simon" as the description (matches the original
# work config). Groups match the shared defaults (networkmanager, wheel).
_:
{
  nixos.hosts."TSBW-W01800" =
    { lib, pkgs, ... }:

    {
      users.users."jaide" = {
        description = lib.mkForce "Simon";
        extraGroups = lib.mkForce [ "networkmanager" "wheel" "wireshark" "_lldpd" "libvirtd" ];
        packages = with pkgs; [
          kdePackages.kate
        ];
      };
    }
  ;
}
