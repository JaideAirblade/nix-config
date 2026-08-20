# Direct-link networking: UwU desktop routes through Luna-Server.
#
# Physical topology (changed 2026-08-08):
#   UwU enp10s0 (Realtek 1GbE) -- Luna-Server eth0 (r8152 USB 2.5GbE)
#
# UwU now gets internet + DNS through Luna-Server instead of going through
# the apartment router directly. The direct link uses a /30 subnet:
#   Luna-Server  -> 10.10.0.1/30  (gateway + AdGuard Home DNS)
#   UwU         -> 10.10.0.2/30  (client)
#
# UwU's WiFi (wlp7s0) remains on the apartment router LAN as a fallback.
# The wired direct-link connection has a lower route metric (100 vs 300)
# so internet traffic prefers the Luna-Server path.
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
    { pkgs, ... }:

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
            id = "Direct Link (Luna-Server)";
            type = "ethernet";
            interface-name = linkIface;
            autoconnect = true;
            permissions = "";
          };
          ethernet = { };
          ipv4 = {
            method = "manual";
            addresses = "${linkIP}/30, ${gatewayIP}";
            # Route the internet through Luna-Server. Lower metric = preferred
            # over WiFi (which NM assigns metric 300+ via DHCP).
            routes = "0.0.0.0/0, ${gatewayIP}, 100";
            # Use AdGuard Home on Luna-Server as DNS (ignore DHCP DNS).
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
      # Pin resolv.conf to AdGuard on Luna-Server with public DNS fallbacks.
      # The NM profile also sets per-connection DNS, but we keep this as the
      # system-wide fallback so nothing depends on NM having connected yet at
      # boot time. Search domains mirror the NM profile: netbird.cloud
      # (magic-DNS) + fritz.box (LAN).
      #
      # Fallback chain: AdGuard on Luna-Server (gatewayIP) → Cloudflare
      # (1.1.1.1) → Quad9 (9.9.9.9). The `timeout:1 attempts:2 rotate` options
      # are critical: glibc tries 5s × 5 retries per server by default, which
      # means when Luna-Server is down (no PSU / off / AdGuard crashed) every
      # DNS lookup blocks for ~10s before hitting 1.1.1.1. With these tunings,
      # a dead primary adds at most ~2s of latency before the fallback fires.
      # `rotate` spreads queries across servers so a single bad resolver
      # doesn't poison latency for everyone.
      networking.nameservers = [ gatewayIP "1.1.1.1" "9.9.9.9" ];
      networking.search = [ "netbird.cloud" "fritz.box" ];
      networking.resolvconf.enable = false;
      environment.etc."resolv.conf".text = ''
        nameserver ${gatewayIP}
        nameserver 1.1.1.1
        nameserver 9.9.9.9
        search netbird.cloud fritz.box
        options edns0 trust-ad timeout:1 attempts:2 rotate
      '';

      # --- Direct-link failover watchdog -----------------------------------
      # When Luna-Server is down (e.g. forgotten power supply, on the desk
      # without juice), the /30 link to 10.10.0.1 still comes up because the
      # Realtek end negotiates fine — but AdGuard is unreachable and the
      # default route through it blackholes all traffic. Symptom on UwU: every
      # DNS lookup takes 10s, apps appear offline even though wifi is working.
      #
      # We probe the AdGuard DoT/DoH/port-53 endpoint every 30s. When 10.10.0.1
      # is unreachable for 3 consecutive probes, we bump the NM connection's
      # route-metric to 1000 (so the wifi default route at metric 300 wins)
      # AND rewrite /etc/resolv.conf to put the cloud resolvers first. When
      # the server comes back, we restore metric 100 and put AdGuard first
      # again. The state file lives in /var/lib/direct-link-watchdog so it
      # survives rebuilds.
      systemd.services.direct-link-watchdog = {
        description = "Failover direct-link to wifi when Luna-Server (10.10.0.1) is unreachable";
        wantedBy = [ "multi-user.target" ];
        after = [ "NetworkManager.service" ];
        wants = [ "NetworkManager.service" "network-online.target" ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "10s";
          ExecStart = let
            watchdogScript = pkgs.writeShellScript "direct-link-watchdog" ''
              #!/usr/bin/env bash
              set -u
              GATEWAY="${gatewayIP}"
              PROFILE="Direct Link (Luna-Server)"
              STATE_DIR="/var/lib/direct-link-watchdog"
              STATE_FILE="$STATE_DIR/mode"
              RESOLVCONF="/etc/resolv.conf"
              # Bash ARRAY — not a single string. Without arrays, "1.1.1.1 9.9.9.9"
              # preserves the space when later passed inside double quotes,
              # which made the failover-mode resolv.conf contain a literal
              #   nameserver 1.1.1.1 9.9.9.9
              # line that glibc refused to parse. Caught in live verification.
              SECONDARIES=("1.1.1.1" "9.9.9.9")
              PROBE_HOST="dns.cloudflare.com"
              FAIL_THRESHOLD=3
              PASS_THRESHOLD=3
              mkdir -p "$STATE_DIR"

              # Current state: "primary" or "fallback"
              mode() {
                cat "$STATE_FILE" 2>/dev/null || echo primary
              }
              set_mode() {
                echo "$1" > "$STATE_FILE"
              }

              set_route_metric() {
                local metric="$1"
                # `nmcli connection modify` is idempotent — writing the new
                # metric is enough; NM rebuilds the routes on the next DHCP
                # lease / SIGHUP. We deliberately do NOT `nmcli connection up`
                # because that would yank the link down and back up, which
                # triggers spurious DHCP events and a brief networking blip.
                # Bail silently if the connection does not exist yet (NM may
                # still be creating it on first boot).
                nmcli connection show "$PROFILE" >/dev/null 2>&1 || return 0
                nmcli connection modify "$PROFILE" \
                  ipv4.route-metric "$metric" \
                  ipv6.route-metric "$metric" >/dev/null 2>&1 || true
              }
              nudge_routes() {
                # Force NM to re-evaluate routes after a metric change without
                # bouncing the link. `device reapply` reapplies the active
                # connection's settings — this is the modern NM-safe way to
                # pick up `ipv4.route-metric` from a live modify.
                nmcli connection show "$PROFILE" >/dev/null 2>&1 || return 0
                local dev
                dev="$(nmcli -t -f DEVICE connection show "$PROFILE" --active 2>/dev/null | head -1)"
                [ -n "$dev" ] || return 0
                nmcli device reapply "$dev" >/dev/null 2>&1 || true
              }

              # Atomic resolv.conf swap via mktemp + mv (symlink-safe).
              write_resolv() {
                # write_resolv <primary_ip> <secondary_ip> [<secondary_ip> ...]
                # Emits one `nameserver <ip>` line per IP. Order = the order of
                # args, since glibc tries them in resolv.conf order.
                local tmp
                tmp="$(mktemp)"
                {
                  for ns in "$@"; do
                    echo "nameserver $ns"
                  done
                  echo "search netbird.cloud fritz.box"
                  echo "options edns0 trust-ad timeout:1 attempts:2 rotate"
                } > "$tmp"
                mv -f "$tmp" "$RESOLVCONF"
                chmod 644 "$RESOLVCONF"
              }

              probe() {
                # TCP connect to the gateway's port 53 within 1s. Faster than
                # `dig`, and AdGuard Home always listens on port 53 by default.
                ${pkgs.busybox}/bin/busybox nc -w 1 -z "$GATEWAY" 53 >/dev/null 2>&1
              }

              fail_count=0
              pass_count=0
              while true; do
                sleep 30
                if probe; then
                  pass_count=$((pass_count + 1))
                  fail_count=0
                  if [ "$(mode)" = fallback ] && [ "$pass_count" -ge "$PASS_THRESHOLD" ]; then
                    echo "[$(date -Iseconds)] Luna-Server reachable again, restoring primary"
                    set_route_metric 100
                    nudge_routes
                    write_resolv "$GATEWAY" "''${SECONDARIES[@]}"
                    set_mode primary
                  fi
                else
                  fail_count=$((fail_count + 1))
                  pass_count=0
                  if [ "$(mode)" = primary ] && [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
                    echo "[$(date -Iseconds)] Luna-Server unreachable ($fail_count consecutive failures), failing over to cloud DNS + wifi route"
                    set_route_metric 1000
                    nudge_routes
                    # Reorder: put cloud fallbacks first, keep gateway last as
                    # a future-restore target.
                    write_resolv "''${SECONDARIES[@]}" "$GATEWAY"
                    set_mode fallback
                  fi
                fi
              done
            '';
          in
            "/bin/sh -c 'exec ${watchdogScript}'";
        };
      };

    }
  ;
}
