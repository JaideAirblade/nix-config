# Direct-link networking: UwU desktop routes through UwU-Server.
#
# Physical topology (changed 2026-08-08):
#   UwU enp10s0 (Realtek 1GbE) -- UwU-Server eth0 (r8152 USB 2.5GbE)
#
# UwU now gets internet + DNS through UwU-Server instead of going through
# the apartment router directly. The direct link uses a /30 subnet:
#   UwU-Server  -> 10.10.0.1/30  (gateway + AdGuard Home DNS)
#   UwU         -> 10.10.0.2/30  (client)
#
# UwU's WiFi (wlp7s0) remains on the apartment router LAN as a fallback.
# The wired direct-link connection has a lower metric (higher priority)
# so internet traffic prefers the UwU-Server path.
_:
{
  nixos.hosts."UwU" =
    { pkgs, ... }:

    let
      linkIface = "enp10s0";
      linkIP = "10.10.0.2";
      gatewayIP = "10.10.0.1";
    in
    {
      # Mark enp10s0 as unmanaged by NetworkManager and assign the static
      # IP via a systemd oneshot. NM keyfiles via environment.etc don't
      # work (NM ignores symlinks), so this is the direct approach.
      networking.networkmanager.unmanaged = [ "${linkIface}" ];

      systemd.services.direct-link-ip = {
        description = "Assign static IP to direct-link interface ${linkIface}";
        after = [ "network-pre.target" ];
        before = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [ pkgs.iproute2 ];
        script = ''
          ip link set ${linkIface} up
          ip addr add ${linkIP}/30 dev ${linkIface} 2>/dev/null || true
          ip route replace default via ${gatewayIP} dev ${linkIface} metric 100 2>/dev/null || true
        '';
      };

      # Use AdGuard Home on UwU-Server as the system DNS. Tailscale's
      # MagicDNS (100.100.100.100) was the default but we want all DNS
      # to go through our own ad-blocking recursive resolver.
      networking.nameservers = [ gatewayIP ];
      networking.search = [ "tail542648.ts.net" "fritz.box" ];
      # Don't let resolvconf/NetworkManager overwrite our DNS setting.
      networking.resolvconf.enable = false;
      environment.etc."resolv.conf".text = ''
        nameserver ${gatewayIP}
        search tail542648.ts.net fritz.box
        options edns0 trust-ad
      '';

      # Tell Tailscale not to manage DNS -- we use AdGuard Home via the
      # direct link. Without this, Tailscale overwrites /etc/resolv.conf
      # with MagicDNS (100.100.100.100) on every tailscaled restart.
      services.tailscale.extraSetFlags = [ "--accept-dns=false" ];
    }
  ;
}