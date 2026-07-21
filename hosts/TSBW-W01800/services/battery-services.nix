# Battery-aware service management.
#
# Disables unnecessary services on battery to save power:
#   - geoclue: DMS enables it (mkDefault true) for weather/location, but
#     it can't query location on this laptop (WiFi scanning fails, can't
#     reach api.beacondb.net). Disabled entirely — it's dead weight.
#   - dnsproxy: DoH proxy to Cloudflare/Quad9/Google. On battery, stop it
#     and fall back to the DHCP DNS server directly (saves the TLS
#     connection overhead + process memory). On AC, restart dnsproxy and
#     point resolv.conf back to 127.0.0.1.
#   - smartd: polls NVMe SMART attributes periodically, waking the SSD.
#     Stopped on battery — disk health can wait for AC.
#   - avahi: mDNS/DNS-SD sends periodic multicast packets. Stopped on
#     battery — printer/service discovery can wait for AC.
{ lib, pkgs, ... }:

{
  # Geoclue — disabled entirely. DMS enables it with mkDefault true for
  # weather/location, but it fails to query location ("No WiFi networks
  # found", "No route to host to api.beacondb.net"). Location provider is
  # "manual" (not geoclue2), so timezone doesn't depend on it either.
  services.geoclue2.enable = lib.mkForce false;

  # dnsproxy battery management — systemd service that:
  #   - On battery: stops dnsproxy, rewrites /etc/resolv.conf to use the
  #     DHCP DNS server directly (from NetworkManager).
  #   - On AC: starts dnsproxy, rewrites /etc/resolv.conf to 127.0.0.1.
  #
  # Triggered by power_supply udev change events (in power.nix) and at
  # boot via graphical.target (after NetworkManager so DHCP DNS is available).
  systemd.services.dnsproxy-battery = {
    description = "Manage dnsproxy on battery (stop) vs AC (start)";
    after = [ "NetworkManager.service" "network.target" ];
    wantedBy = [ "graphical.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.networkmanager pkgs.procps ];
    script = ''
      ac=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null || echo 0)
      if [ "$ac" = "1" ]; then
        # AC: start dnsproxy, point resolv.conf to it
        systemctl start dnsproxy.service 2>/dev/null || true
        cat > /etc/resolv.conf << 'RESOLV'
nameserver 127.0.0.1
search ausbildung.tsbw.de tsbw.de
options edns0 trust-ad
RESOLV
      else
        # Battery: stop dnsproxy, use DHCP DNS directly
        systemctl stop dnsproxy.service 2>/dev/null || true
        # Get DNS from NetworkManager (first interface with a DNS server)
        dhcp_dns=""
        for dev in $(nmcli -t -f GENERAL.DEVICE dev show 2>/dev/null | cut -d: -f2); do
          for dns in $(nmcli -t -f IP4.DNS dev show "$dev" 2>/dev/null | cut -d: -f2); do
            [ -n "$dns" ] && dhcp_dns="$dhcp_dns $dns"
          done
          [ -n "$dhcp_dns" ] && break
        done
        if [ -n "$dhcp_dns" ]; then
          tmp=$(mktemp)
          echo "search ausbildung.tsbw.de tsbw.de" > "$tmp"
          echo "options edns0 trust-ad" >> "$tmp"
          for ip in $dhcp_dns; do
            echo "nameserver $ip"
          done >> "$tmp"
          mv "$tmp" /etc/resolv.conf
        else
          # Fallback: use Cloudflare DNS directly
          cat > /etc/resolv.conf << 'RESOLV'
nameserver 1.1.1.1
nameserver 9.9.9.9
search ausbildung.tsbw.de tsbw.de
options edns0 trust-ad
RESOLV
        fi
      fi
    '';
  };

  # smartd + avahi battery management — stop on battery, start on AC.
  # smartd polls NVMe SMART attributes (wakes SSD), avahi sends mDNS
  # multicast packets. Both are unnecessary on battery.
  systemd.services.services-battery = {
    description = "Stop smartd + avahi on battery, start on AC";
    wantedBy = [ "graphical.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ac=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null || echo 0)
      if [ "$ac" = "1" ]; then
        systemctl start smartd.service 2>/dev/null || true
        systemctl start avahi-daemon.service 2>/dev/null || true
      else
        systemctl stop smartd.service 2>/dev/null || true
        systemctl stop avahi-daemon.service 2>/dev/null || true
      fi
    '';
  };
}