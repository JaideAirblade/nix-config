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
        # `netbird-mesh` is added so the DMS NetbirdStatus plugin +
        # `netbird` CLI shim can talk to the daemon's unix socket at
        # /var/run/netbird-mesh/sock. The role module tries to add it
        # via lib.mkAfter, but this host mkForces the entire
        # extraGroups list (work-only override), so we must include
        # it in the forced list here. Adding it to the canonical
        # personal list would silently disappear under mkForce.
        extraGroups = lib.mkForce [ "networkmanager" "wheel" "wireshark" "_lldpd" "libvirtd" "netbird-mesh" ];
        packages = with pkgs; [
          kdePackages.kate
        ];
      };
    }
  ;
}
