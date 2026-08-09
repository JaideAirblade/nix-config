# Direct-link networking: UwU-Server acts as gateway + DNS for UwU desktop.
#
# Physical topology (changed 2026-08-08):
#   UwU-Server eth0 (r8152 USB 2.5GbE) -- UwU enp10s0 (Realtek 1GbE)
#
# UwU no longer goes through the apartment router for internet -- it routes
# through UwU-Server instead. UwU-Server still gets its own internet via
# eno1 (the apartment router LAN), and forwards UwU's traffic out the same
# path. DNS is AdGuard Home (ad/tracker blocking) backed by Unbound
# (recursive resolver) -- both on UwU-Server, listening on the direct-link
# interface so UwU (and only UwU) can reach them.
#
# Subnet: 10.10.0.0/30
#   UwU-Server eth0  -> 10.10.0.1/30  (gateway + DNS)
#   UwU enp10s0      -> 10.10.0.2/30  (client)
_:
{
  nixos.hosts."UwU-Server" =
    { lib, pkgs, ... }:

    let
      # Direct-link interface on UwU-Server (r8152 USB 2.5GbE adapter).
      linkIface = "eth0";
      linkIP = "10.10.0.1";
      linkSubnet = "10.10.0.0/30";
      # The upstream (internet-facing) interface -- eno1 on the apartment
      # router LAN. NAT masquerades UwU's traffic out this interface.
      uplinkIface = "eno1";
    in
    {
      # --- Static IP on the direct-link interface ---------------------------
      # network-addresses-eth0.service doesn't exist under NetworkManager,
      # and NM ignores keyfile symlinks from environment.etc. Instead we
      # mark eth0 as unmanaged by NM and use a systemd oneshot to assign
      # the static IP at boot. This is the simplest approach that doesn't
      # fight NM's connection management.
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
        '';
      };

      # --- IP forwarding + NAT (UwU-Server as gateway for UwU) --------------
      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = true;
      };

      networking.nftables.enable = true;
      networking.nat = {
        enable = true;
        # Masquerade UwU's traffic out the uplink interface (eno1 -> router).
        externalInterface = uplinkIface;
        internalInterfaces = [ linkIface ];
      };

      # --- Firewall: allow DNS on the direct-link interface ----------------
      networking.firewall.interfaces.${linkIface} = {
        allowedTCPPorts = [ 53 ];
        allowedUDPPorts = [ 53 ];
      };

      # --- Unbound: recursive DNS resolver ----------------------------------
      # Unbound does full recursive resolution (talks to root servers
      # directly), caches results. AdGuard Home forwards to Unbound for
      # actual resolution. This gives ad-blocking + privacy (no third-party
      # recursive DNS like Cloudflare/Google).
      services.unbound = {
        enable = true;
        settings = {
          server = {
            interface = [ "127.0.0.1" ];
            port = 5335;
            do-ip4 = true;
            do-ip6 = false;
            do-udp = true;
            do-tcp = true;
            # Aggressive caching for speed.
            cache-min-ttl = 300;
            cache-max-ttl = 86400;
            # Larger cache — default is 4MB, 64MB covers ~400k entries.
            msg-cache-size = "64m";
            rrset-cache-size = "128m";
            # Prefetch popular records before they expire.
            prefetch = true;
            prefetch-key = true;
            # Serve expired entries while refreshing in background.
            serve-expired = true;
            serve-expired-ttl = 3600;
            # More threads for parallel resolution.
            num-threads = 4;
            # Faster outgoing port range (avoids kernel port allocation overhead).
            outgoing-range = 4096;
            # Hardening.
            harden-dnssec-stripped = true;
            harden-glue = true;
            harden-below-nxdomain = true;
            val-clean-additional = true;
            # Privacy: minimise QNAME to reduce information leakage.
            qname-minimisation = true;
            # Access control -- localhost only (AdGuard Home forwards here).
            access-control = [ "127.0.0.1/32 allow" ];
          };
        };
      };

      # --- AdGuard Home: ad/tracker blocking DNS ----------------------------
      # Binds to 0.0.0.0 so it doesn't need to wait for eth0 to have its
      # IP. The firewall restricts access to the direct-link interface
      # and mesh only -- binding wide is safe because the firewall
      # blocks external access.
      #
      # NixOS module: `host` + `port` set the WEB UI bind address, NOT DNS.
      # The DNS listener is configured in settings.dns.listen_port.
      services.adguardhome = {
        enable = true;
        host = "0.0.0.0";
        port = 3000;
        openFirewall = false;
        mutableSettings = true;
        settings = {
          http = {
            address = "0.0.0.0:3000";
            session_ttl = "720h";
          };
          dns = {
            bind_address = "0.0.0.0";
            listen_port = 53;
            # Per-domain upstream: empty for now. The previous Tailscale
            # routing ([/tail542648.ts.net/]100.100.100.100) is gone with
            # Tailscale. Netbird magic-DNS is served by the netbird-mesh
            # daemon directly (when systemd-resolved is enabled on the
            # client). AdGuard falls back to Unbound for everything else;
            # UwU-side netbird hostnames resolve via netbird-mesh's
            # nameserver on the Tailscale-deprecated path. The split-horizon
            # upstream_dns routing for the netbird-cloud domain is a
            # deferred Phase 3 task (see docs/netbird-mesh.md).
            upstream_dns = [
              "127.0.0.1:5335"
            ];
            bootstrap_dns = [
              "1.1.1.1"
              "9.9.9.9"
            ];
            cache_size = 4096;
            cache_ttl_min = 60;
            cache_ttl_max = 86400;
            cache_optimistic = true;
            filtering_enabled = true;
            filters = [
              {
                name = "AdGuard DNS filter";
                url = "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt";
                enabled = true;
              }
              {
                name = "AdAway Default Blocklist";
                url = "https://adaway.org/hosts.txt";
                enabled = true;
              }
            ];
            allowed_clients = [ linkSubnet "127.0.0.1/32" ];
            ratelimit = 0;
          };
        };
      };

      # Open AdGuard Home web UI on the mesh interface (for remote admin).
      networking.firewall.interfaces.wt0.allowedTCPPorts =
        lib.mkAfter [ 3000 ];
    }
  ;
}