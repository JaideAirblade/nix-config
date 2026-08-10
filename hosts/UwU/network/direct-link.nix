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
# The wired direct-link connection has a lower route metric (100 vs 300)
# so internet traffic prefers the UwU-Server path.
#
# HISTORY: This used to use a systemd oneshot + `networking.networkmanager.unmanaged`
# because NM keyfile symlinks via environment.etc didn't work. As of 2026-08-08
# we switched to `networking.networkmanager.ensureProfiles`, which writes proper
# NM keyfiles that NM actually manages. This means:
#   - enp10s0 shows up in nmcli / DMS bar as a real connection
#   - You can toggle it on/off from the network widget
#   - NM handles link monitoring and failover
_:
{
  nixos.hosts."UwU" =
    { ... }:

    let
      linkIface = "enp10s0";
      linkIP = "10.10.0.2";
      gatewayIP = "10.10.0.1";
    in
    {
      # --- NetworkManager-managed direct-link profile -----------------------
      # Replaces the old systemd oneshot + unmanaged hack. NM now owns
      # enp10s0 as a proper managed connection with a static IP.
      networking.networkmanager.ensureProfiles.profiles = {
        direct-link = {
          connection = {
            id = "Direct Link (UwU-Server)";
            type = "ethernet";
            interface-name = linkIface;
            autoconnect = true;
            permissions = "";
          };
          ethernet = { };
          ipv4 = {
            method = "manual";
            addresses = "${linkIP}/30, ${gatewayIP}";
            # Route the internet through UwU-Server. Lower metric = preferred
            # over WiFi (which NM assigns metric 300+ via DHCP).
            routes = "0.0.0.0/0, ${gatewayIP}, 100";
            # Use AdGuard Home on UwU-Server as DNS (ignore DHCP DNS).
            dns = "${gatewayIP}";
            # DNS search domains. Netbird magic-DNS lives under
            # `netbird.cloud` (managed by netbird.io's public DNS, not
            # the local AdGuard), so explicit `Host` blocks in
            # /etc/luna/ssh_config are the right ergonomic path —
            # the bare suffix isn't on this list. `fritz.box` stays
            # for LAN name resolution.
            dns-search = "netbird.cloud;fritz.box";
            ignore-auto-dns = true;
            route-metric = 100;
          };
          ipv6 = {
            method = "disabled";
          };
        };
      };

      # --- System DNS (resolv.conf) ----------------------------------------
      # Pin resolv.conf to AdGuard. The NM profile also sets per-connection
      # DNS, but we keep this as the system-wide fallback so nothing depends
      # on NM having connected yet at boot time. The search domain list
      # mirrors the NM profile: netbird.cloud (magic-DNS) + fritz.box
      # (LAN).
      networking.nameservers = [ gatewayIP ];
      networking.search = [ "netbird.cloud" "fritz.box" ];
      networking.resolvconf.enable = false;
      environment.etc."resolv.conf".text = ''
        nameserver ${gatewayIP}
        search netbird.cloud fritz.box
        options edns0 trust-ad
      '';

    }
  ;
}
