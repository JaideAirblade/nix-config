# Network configuration for the Projet-Printserver VM.
#
# Static IP in the ad-lab network (192.168.100.0/24). The print server
# needs a stable IP so Windows clients can map \\192.168.100.20\printer
# and so the DC can resolve the print server's SPN.
#
# DNS points to the domain controller (192.168.100.10) so AD SRV records
# and Kerberos lookups work. The search domain is lab.local so short
# names resolve correctly.
_:
{
  nixos.hosts."Projet-Printserver" =
    { lib, ... }:

    {
      networking.hostName = "Projet-Printserver";

      # Static IP on the ad-lab network.
      networking.interfaces.eth0.ipv4.addresses = [
        {
          address = "192.168.100.20";
          prefixLength = 24;
        }
      ];

      # Default gateway is the ad-lab NAT (for outbound updates).
      networking.defaultGateway = "192.168.100.1";

      # DNS points to the domain controller for AD name resolution.
      networking.nameservers = [ "192.168.100.10" ];
      networking.search = [ "lab.local" ];

      # Disable NetworkManager — static config is simpler for a VM.
      # mkForce overrides the common module's mkDefault true.
      networking.networkmanager.enable = lib.mkForce false;

      # Disable systemd-resolved — the DC handles DNS.
      services.resolved.enable = false;
    }
  ;
}
