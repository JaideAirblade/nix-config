# Stateful default-deny firewall using NixOS's nftables backend.
#
# Keeping networking.firewall enabled is important: NixOS service options such
# as Steam's openFirewall flags and interface-scoped VPN rules contribute to
# this firewall. Replacing it with an unrelated raw ruleset silently discards
# those declarations.
_:
{
  nixos.modules.common =
    _:
    {
      networking.nftables.enable = true;

      networking.firewall = {
        enable = true;

        # Preserve the previous stealth behavior: unsolicited echo requests are
        # dropped, while established/related traffic and required DHCP traffic are
        # handled by the NixOS firewall implementation.
        allowPing = false;
        logRefusedConnections = false;

        # Local discovery used by Avahi/GVfs/DMS.
        allowedUDPPorts = [ 5353 ];
      };
    }
  ;
}
