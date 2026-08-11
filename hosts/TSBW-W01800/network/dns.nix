# DNS configuration — AdGuard default + DoH fallback for everything except
# the DHCP-advertised internal domains.
#
# dnsproxy (AdGuard) with a multi-tier upstream chain:
#   1. Per-domain (most specific first):
#      a. *.netbird.cloud → UwU-Server's AdGuard at 100.77.228.137:53.
#         AdGuard forwards *.netbird.cloud to its local netbird daemon
#         on 127.0.0.1:5353 — so a single hardcoded upstream here
#         resolves every mesh hostname from this host.
#      b. *.tsbw.de / *.ausbildung.tsbw.de → DHCP DNS servers directly
#         (file written by the NM dispatcher below). These domains
#         are authoritative on the apartment's DHCP server; routing
#         them through AdGuard would add a mesh hop and end in
#         NXDOMAIN (AdGuard → Unbound doesn't know tsbw.de).
#   2. Default catch-all:
#      Public domains → UwU-Server's AdGuard at 100.77.228.137:53.
#      AdGuard does ad-blocking locally and forwards to its own
#      Unbound for full recursive resolution (no third-party leak).
#      One resolver chain across the fleet.
#   3. Fallback (--fallback flag, only fires on connection error — NOT
#      on NXDOMAIN, per the dnsproxy docs and confirmed in our
#      earlier session notes):
#      DoH upstreams (Cloudflare, Quad9, Google, AdGuard) — used
#      only when UwU-Server's AdGuard is unreachable, so the work
#      laptop's DNS keeps working even when the apartment server is
#      offline.
#
# A NM dispatcher script writes the DHCP DNS IPs (only from interfaces
# carrying the tsbw.de search domain) to an upstream file in dnsproxy's
# [/domain/]server syntax and restarts dnsproxy on network changes.
#
# Why not route *.tsbw.de through AdGuard? AdGuard → Unbound → public
# DNS will not know *.tsbw.de (it's a private DHCP-advertised zone),
# so queries end in NXDOMAIN. Per-domain upstreams route internal
# queries to the right server BEFORE the catch-all AdGuard upstream
# is asked.
#
# Boot race: dnsproxy After=NetworkManager, but NM "started" ≠ DHCP lease
# acquired.  The preStart tolerates missing DHCP DNS (writes a placeholder;
# `grep -v` failure is caught with `|| true` and no `set -e`) so ExecStartPre
# never fails.  The NM dispatcher (args: $1=iface, $2=action) fills the real
# upstreams once DHCP completes and restarts dnsproxy.
#
# https://github.com/AdguardTeam/dnsproxy
_:
{
  nixos.hosts."TSBW-W01800" =
    { lib, pkgs, ... }: {
      # Disable systemd-resolved — dnsproxy handles DNS
      services.resolved.enable = false;

      # Stop SmartDNS if it's still running (port conflict)
      services.smartdns.enable = false;
      # Stop CoreDNS if it's still running (port conflict)
      services.coredns.enable = false;

      # dnsproxy as a systemd service.
      #
      # NOT auto-started by multi-user.target — dnsproxy-battery.service is the
      # sole manager of dnsproxy.service (start on AC, stop on battery).  Both
      # wantedBy and the NM dispatcher's systemctl restart would race with
      # dnsproxy-battery at boot, hitting systemd's start rate limit and
      # leaving dnsproxy in failed state.
      systemd.services.dnsproxy = {
        description = "dnsproxy DNS server (DoH + internal domain routing)";
        after = [ "network.target" "NetworkManager.service" ];
        wants = [ "NetworkManager.service" ];
        # Ensure old DNS services are stopped before dnsproxy starts
        before = [ "smartdns.service" "coredns.service" ];
        startLimitBurst = 30;
        startLimitIntervalSec = 60;
        # nmcli is needed in preStart to read DHCP DNS servers
        path = [ pkgs.networkmanager ];

        preStart = ''
          mkdir -p /run/dnsproxy
          # ALWAYS refresh internal-upstreams from current DHCP state.
          # No `set -e` — at boot NetworkManager may have just started and no
          # DHCP lease exists yet.  nmcli returns nothing and the grep would
          # exit 1, killing ExecStartPre.  We tolerate empty output; the NM
          # dispatcher re-fills this file on dhcp4-change events.
          #
          # Only collect DNS from interfaces carrying the tsbw.de search domain,
          # to avoid polluting the upstream list with DNS from unrelated networks.
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
          TMPFILE=$(mktemp /run/dnsproxy/internal-upstreams.txt.XXXXXX)
          if [ -n "''${DNS_SERVERS:-}" ]; then
            for ip in $DNS_SERVERS; do
              echo "[/tsbw.de/]$ip"
            done > "$TMPFILE"
          else
            echo "# No DHCP DNS yet — NM dispatcher will update on dhcp4-change" > "$TMPFILE"
          fi
          mv "$TMPFILE" /run/dnsproxy/internal-upstreams.txt
        '';

        serviceConfig = {
          ExecStart = "${lib.getBin pkgs.dnsproxy}/bin/dnsproxy"
            + " --listen 127.0.0.1"
            + " --port 53"
            # Per-domain (most specific first):
            #   *.netbird.cloud → AdGuard on UwU-Server (mesh DNS chain)
            + " --upstream [/netbird.cloud/]100.77.228.137:53"
            #   *.tsbw.de / *.ausbildung.tsbw.de → DHCP DNS file
            #   (NM dispatcher writes the DHCP-discovered IPs into
            #   /run/dnsproxy/internal-upstreams.txt with [/suffix/]ip
            #   syntax; this file lives in the chain BEFORE the catch-all
            #   AdGuard upstream so internal queries never leave the LAN)
            + " --upstream /run/dnsproxy/internal-upstreams.txt"
            # Default catch-all:
            #   Public domains → UwU-Server's AdGuard (ad-blocking +
            #   Unbound recursive resolution). One resolver chain for
            #   the whole fleet, with ad-blocking uniformly applied.
            + " --upstream 100.77.228.137:53"
            # Fallback (fires ONLY on connection error, NOT on NXDOMAIN):
            #   Public DoH upstreams, used when UwU-Server's AdGuard is
            #   unreachable. Keeps TSBW DNS working even when the
            #   apartment server is offline.
            + " --fallback https://1.1.1.1/dns-query"
            + " --fallback https://9.9.9.9/dns-query"
            + " --fallback https://8.8.8.8/dns-query"
            + " --fallback https://94.140.14.14/dns-query"
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
          # NM dispatcher args: $1 = interface name, $2 = action
          IFACE="$1"
          ACTION="$2"
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

          # Restart dnsproxy so it picks up the new upstreams — but only if
          # it's already running.  dnsproxy-battery.service is the sole
          # authority on whether dnsproxy should be running at all (AC=yes,
          # battery=no).  If we restart it while battery mode has stopped it,
          # we subvert battery management and race with dnsproxy-battery at
          # boot, hitting systemd's start rate limit.  `try-restart` only
          # restarts active units — if dnsproxy is stopped, it's a no-op.
          # `|| true` guards against rate-limit failures so the dispatcher
          # script itself never exits non-zero (NM logs warnings on exit 1).
          systemctl try-restart dnsproxy.service 2>/dev/null || true
        '';
      };

      # Create /etc/resolv.conf as a real writable file (not a store symlink
      # via environment.etc) so the dnsproxy-battery service can rewrite it
      # on power-state changes.  The default content points to dnsproxy on
      # 127.0.0.1; dnsproxy-battery overwrites it on battery/AC transitions.
      systemd.services.resolv-conf-init = {
        description = "Initialize /etc/resolv.conf as a writable file";
        after = [ "NetworkManager.service" "network.target" ];
        before = [ "dnsproxy.service" "dnsproxy-battery.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
                # Remove Nix store symlink if present (from old config using environment.etc)
                if [ -L /etc/resolv.conf ]; then
                  rm /etc/resolv.conf
                fi
                # Write default content (AC mode — dnsproxy listening on 127.0.0.1)
                # The search line lets short names like "serverfarm" expand to
                # "serverfarm.ausbildung.tsbw.de" via glibc's search-domain logic.
                cat > /etc/resolv.conf << 'RESOLV'
          nameserver 127.0.0.1
          search tsbw.de ausbildung.tsbw.de
          options edns0 trust-ad
          RESOLV
                chmod 644 /etc/resolv.conf
        '';
      };

      # Don't let NetworkManager overwrite /etc/resolv.conf
      networking.resolvconf.enable = false;
      networking.networkmanager.dns = lib.mkForce "none";
    }
  ;
}
