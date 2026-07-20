# DNS configuration — DoH for public domains, DHCP DNS for internal domains
#
# dnsproxy (AdGuard) with domain-specific upstreams:
#   1. Public domains → DoH upstreams (Cloudflare, Quad9, Google, AdGuard) —
#      port 443, looks like normal HTTPS traffic, harder to block
#   2. Internal domains (*.tsbw.de) → DHCP DNS servers directly
#   3. A NM dispatcher script writes the DHCP DNS IPs (only from interfaces
#      carrying the tsbw.de search domain) to an upstream file in dnsproxy's
#      [/domain/]server syntax and restarts dnsproxy on network changes.
#
# Why not --fallback?  dnsproxy's --fallback only triggers when upstreams
# are UNREACHABLE (connection error).  DoH upstreams return NXDOMAIN for
# internal domains — a valid DNS response — so --fallback never fires and
# internal domains stay unresolved.  Domain-specific upstreams route the
# query to the right server before DoH is ever asked.
#
# Boot race: dnsproxy After=NetworkManager, but NM "started" ≠ DHCP lease
# acquired.  The preStart tolerates missing DHCP DNS (writes a placeholder;
# `grep -v` failure is caught with `|| true` and no `set -e`) so ExecStartPre
# never fails.  The NM dispatcher fills the real upstreams once DHCP completes.
#
# https://github.com/AdguardTeam/dnsproxy
{lib, pkgs, ...}: {
  # Disable systemd-resolved — dnsproxy handles DNS
  services.resolved.enable = false;

  # Stop SmartDNS if it's still running (port conflict)
  services.smartdns.enable = false;
  # Stop CoreDNS if it's still running (port conflict)
  services.coredns.enable = false;

  # dnsproxy as a systemd service
  systemd.services.dnsproxy = {
    description = "dnsproxy DNS server (DoH + internal domain routing)";
    after = [ "network.target" "NetworkManager.service" ];
    wants = [ "NetworkManager.service" ];
    wantedBy = [ "multi-user.target" ];
    # Ensure old DNS services are stopped before dnsproxy starts
    before = [ "smartdns.service" "coredns.service" ];
    # nmcli is needed in preStart to read DHCP DNS servers
    path = [ pkgs.networkmanager ];

    preStart = ''
      mkdir -p /run/dnsproxy
      # Create internal-upstreams file with current DHCP DNS if it doesn't exist.
      # NOTE: No `set -e` here — at boot, NetworkManager may have just started
      # and no DHCP lease exists yet.  nmcli returns nothing, and the grep in
      # the pipeline would exit 1, killing ExecStartPre.  We tolerate empty
      # output; the NM dispatcher fills this file once DHCP completes.
      #
      # Only collect DNS from interfaces carrying the tsbw.de search domain,
      # to avoid polluting the upstream list with DNS from unrelated networks.
      if [ ! -f /run/dnsproxy/internal-upstreams.txt ]; then
        DNS_SERVERS=""
        for dev in $(nmcli -t -f GENERAL.DEVICE dev show 2>/dev/null | cut -d: -f2); do
          DOMAIN=$(nmcli -t -f IP4.DOMAIN dev show "$dev" 2>/dev/null | cut -d: -f2)
          case " $DOMAIN " in
            *"tsbw.de"*) : ;;
            *) continue ;;
          esac
          for dns in $(nmcli -t -f IP4.DNS dev show "$dev" 2>/dev/null | cut -d: -f2); do
            [ -n "$dns" ] && DNS_SERVERS="$DNS_SERVERS $dns"
          done
        done
        DNS_SERVERS=$(echo "$DNS_SERVERS" | tr ' ' '\n' | sort -u | grep -v '^$' || true)
        if [ -n "''${DNS_SERVERS:-}" ]; then
          for ip in $DNS_SERVERS; do
            echo "[/tsbw.de/]$ip"
          done > /run/dnsproxy/internal-upstreams.txt
        else
          echo "# Placeholder — filled by NM dispatcher" > /run/dnsproxy/internal-upstreams.txt
        fi
      fi
    '';

    serviceConfig = {
      ExecStart = "${lib.getBin pkgs.dnsproxy}/bin/dnsproxy"
        + " --listen 127.0.0.1"
        + " --port 53"
        + " --upstream https://1.1.1.1/dns-query"
        + " --upstream https://9.9.9.9/dns-query"
        + " --upstream https://8.8.8.8/dns-query"
        + " --upstream https://94.140.14.14/dns-query"
        + " --upstream /run/dnsproxy/internal-upstreams.txt"
        + " --cache"
        + " --cache-size 4096";
      Restart = "on-failure";
      RestartSec = "3s";
      # systemd creates /run/dnsproxy automatically before preStart
      RuntimeDirectory = "dnsproxy";
      # Run as root — local DNS proxy needs port 53 and /run/dnsproxy access.
      CapabilityBoundingSet = "cap_net_bind_service";
      AmbientCapabilities = "cap_net_bind_service";
    };
  };

  # NetworkManager dispatcher: writes DHCP DNS servers to an upstream file
  # in dnsproxy's [/domain/]server syntax and restarts dnsproxy on network
  # changes.
  environment.etc."NetworkManager/dispatcher.d/01-dnsproxy-internal-dns" = {
    mode = "0755";
    source = pkgs.writeShellScript "dnsproxy-internal-dns-dispatcher" ''
      ACTION="$1"
      case "$ACTION" in
        up|dhcp4-change|dhcp6-change) ;;
        *) exit 0 ;;
      esac

      # Extract DNS IPs from NetworkManager interfaces that carry the tsbw.de
      # search domain.  This avoids polluting the upstream list with DNS from
      # unrelated networks (e.g. a guest wifi that happens to be connected).
      DNS_SERVERS=""
      for dev in $(nmcli -t -f GENERAL.DEVICE dev show 2>/dev/null | cut -d: -f2); do
        DOMAIN=$(nmcli -t -f IP4.DOMAIN dev show "$dev" 2>/dev/null | cut -d: -f2)
        case " $DOMAIN " in
          *"tsbw.de"*) : ;;  # carries tsbw.de — collect its DNS
          *) continue ;;
        esac
        for dns in $(nmcli -t -f IP4.DNS dev show "$dev" 2>/dev/null | cut -d: -f2); do
          [ -n "$dns" ] && DNS_SERVERS="$DNS_SERVERS $dns"
        done
      done
      # Deduplicate
      DNS_SERVERS=$(echo "$DNS_SERVERS" | tr ' ' '\n' | sort -u | grep -v '^$' || true)

      mkdir -p /run/dnsproxy
      TMPFILE=$(mktemp /run/dnsproxy/internal-upstreams.txt.XXXXXX)
      if [ -n "$DNS_SERVERS" ]; then
        for ip in $DNS_SERVERS; do
          echo "[/tsbw.de/]$ip"
        done > "$TMPFILE"
      else
        echo "# No DHCP DNS" > "$TMPFILE"
      fi
      mv "$TMPFILE" /run/dnsproxy/internal-upstreams.txt

      systemctl restart dnsproxy.service
    '';
  };

  # Make the system use dnsproxy as its DNS resolver
  # The search line lets short names like "serverfarm" expand to
  # "serverfarm.ausbildung.tsbw.de" via glibc's search-domain logic.
  environment.etc."resolv.conf".text = ''
    nameserver 127.0.0.1
    search ausbildung.tsbw.de tsbw.de
    options edns0 trust-ad
  '';

  # Don't let NetworkManager overwrite /etc/resolv.conf
  networking.resolvconf.enable = false;
  networking.networkmanager.dns = lib.mkForce "none";
}