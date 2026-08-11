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
        # mutableSettings = false → on every restart, pre-start does a
        # clean `cp` of the Nix-generated YAML over the on-disk one
        # instead of merging. On-disk state mirrors Nix source exactly,
        # and any partial/poisoned state from a previous bad deploy
        # gets wiped on the next restart. Web UI changes are NOT
        # persisted, but for our setup everything is Nix-managed.
        mutableSettings = false;
        settings = {
          http = {
            address = "0.0.0.0:3000";
            session_ttl = "720h";
          };
          dns = {
            bind_address = "0.0.0.0";
            listen_port = 53;
            # Split-horizon upstream: per-domain inline DNS forward
            # (AdGuard's `[/suffix/]<upstream>` syntax, exact-match on
            # the suffix). Wildcard domains are routed to a different
            # upstream than everything else, so a single AdGuard
            # instance can answer both "public" DNS (via Unbound) and
            # private-mesh DNS (via the local netbird daemon) without
            # leaking mesh names to public resolvers.
            #
            # The netbird daemon on this host binds its mesh DNS
            # resolver on 127.0.0.1:5353 (set via
            # `services.netbirdMesh.dnsResolverAddress` in
            # hosts/UwU-Server/default.nix). Port 53 is taken by
            # AdGuard itself; 5353 is the standard mDNS port and
            # avoids the CAP_NET_BIND_SERVICE cap the netbird
            # daemon would otherwise need to bind below 1024.
            #
            # Other queries route to Unbound (full recursive
            # resolution from root, no third-party resolver). The
            # previous Tailscale per-domain routing
            # ([/tail542648.ts.net/]100.100.100.100) is gone with
            # Tailscale (see commit `chore(mesh): drop Tailscale
            # entirely`). The Porkbun A records for jaidechan.moe
            # and its subdomains still point at the netbird mesh IP
            # 100.77.228.137, so `dig jaidechan.moe @127.0.0.1`
            # resolves correctly through the Unbound path.
            upstream_dns = [
              "[/netbird.cloud/]127.0.0.1:5353"
              "127.0.0.1:5335"
            ];
            # Explicit empty bootstrap_dns: AdGuard's runtime default is
            # Cloudflare + Quad9 (1.1.1.1, 9.9.9.9). Even though
            # upstream_dns is an IP (no resolution needed), AdGuard's
            # own internal lookups (filter list updates, license check)
            # use bootstrap_dns. Set it to empty so AdGuard uses Unbound
            # (its own resolver) for those lookups instead of leaking to
            # Cloudflare/Quad9. The mutableSettings = true flag means
            # AdGuard's in-memory state is persisted to disk on every
            # restart, so we have to explicitly clear this in the Nix
            # config to prevent it from being restored from the
            # pre-existing on-disk YAML.
            bootstrap_dns = [];
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
            # Per AdGuard's runtime default the allowed_clients list
            # is 127.0.0.0/8 (localhost only) and any external DNS
            # query returns REFUSED. We extend it to:
            #   - the direct-link subnet (10.10.0.0/30) — UwU uses
            #     the gateway IP 10.10.0.1 as its system resolver
            #   - loopback (127.0.0.1/32) — AdGuard self-queries for
            #     filter-list updates + license checks
            #   - the netbird mesh subnet (100.77.0.0/16) — TSBW
            #     reaches AdGuard at the UwU-Server mesh IP
            #     (100.77.228.137) over the netbird tunnel and chains
            #     `*.netbird.cloud` into the local netbird daemon
            #     (see hosts/UwU-Server/network/direct-link.nix wt0
            #     firewall below + services.netbirdMesh.dnsResolverAddress).
            allowed_clients = [
              linkSubnet
              "127.0.0.1/32"
              "100.77.0.0/16"
            ];
            ratelimit = 0;
          };
          # --- DoT (DNS-over-TLS, RFC 7858) on port 853 --------------------
          # Used by Android "Private DNS" feature (Samsung phones,
          # uwu-phone on the netbird mesh, etc.). The phone pins a
          # hostname like `dns.jaidechan.moe`; the LE wildcard cert for
          # *.jaidechan.moe is mounted into AdGuard's service namespace
          # via systemd LoadCredential= (see below) so the DynamicUser
          # can read it without widening permissions on /var/lib/acme.
          #
          # AdGuard's YAML schema (v0.107.x) has `tls` at the TOP level
          # of the file (sibling of `dns:`, NOT a child of it). The path
          # fields (`certificate_path` / `private_key_path`) point at
          # files; AdGuard reads them at startup. The empty strings for
          # `certificate_chain` / `private_key` (inline PEM fields) are
          # deliberately left empty since we're using the file-based
          # form.
          #
          # Only reachable on the mesh firewall (wt0) — direct-link
          # (eth0) and the public internet (eno1) are NOT in scope. The
          # phone reaches AdGuard at 100.77.228.137:853 over the netbird
          # tunnel.
          tls = {
            enabled = true;
            server_name = "dns.jaidechan.moe";
            # CRITICAL: tls.enabled=true also switches on AdGuard's
            # HTTPS WEB UI, whose default port is 443 — which nginx
            # already owns on this host. AdGuard PANICS on the bind
            # conflict (webapi.serveTLS → RecoverAndExit) and the
            # whole process dies, taking plaintext :53 down with it.
            # port_https = 0 disables the HTTPS web UI (and DoH, which
            # rides the same port) while keeping DoT on 853.
            force_https = false;
            port_https = 0;
            port_dns_over_tls = 853;
            port_dns_over_quic = 0;       # we don't need DoQ, only DoT
            port_dnscrypt = 0;            # not running DNSCrypt either
            # AdGuard runs as the fixed `adguardhome` system user
            # (DynamicUser disabled below), which is a member of the
            # `nginx` group — the same group the acme module chowns
            # /var/lib/acme/jaidechan.moe to (0750 acme:nginx, files
            # 0640 via the postRun chmod in dashboard.nix). So the
            # direct paths below are group-readable, no LoadCredential
            # gymnastics needed.
            certificate_path = "/var/lib/acme/jaidechan.moe/fullchain.pem";
            private_key_path  = "/var/lib/acme/jaidechan.moe/key.pem";
            strict_sni_check = false;     # wildcard cert, SNIs vary
          };
        };
      };
      # Fixed system user for AdGuard, replacing the module's
      # DynamicUser=yes. Needed for DoT cert access: systemd
      # LoadCredential= mounts creds into a root-only 0500 dir that
      # AdGuard's cert WATCHER can't traverse as a dynamic UID
      # (tls_manager: permission denied), so the cred path is a dead
      # end. Instead: fixed user in the `nginx` group, reading the
      # LE wildcard cert directly from /var/lib/acme/jaidechan.moe/
      # (0750 acme:nginx; files 0640 via postRun chmod in
      # dashboard.nix).
      users.users.adguardhome = {
        isSystemUser = true;
        group = "adguardhome";
        extraGroups = [ "nginx" ];
      };
      users.groups.adguardhome = { };
      systemd.services.adguardhome.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "adguardhome";
        Group = "adguardhome";
      };

      # Open AdGuard Home on the mesh interface. The mesh peer
      # (TSBW-W01800, currently the only non-private node) reaches
      # AdGuard at the mesh IP 100.77.228.137:53 over the netbird
      # tunnel so its dnsproxy can forward `*.netbird.cloud` queries
      # to the local resolver (which then forwards to the local
      # netbird daemon at 127.0.0.1:5353). UwU doesn't need this —
      # its resolv.conf is pinned to AdGuard via the direct-link IP
      # (10.10.0.1), not the mesh IP.
      #
      # 853/tcp added 2026-08-11 for DoT — Android Private DNS for
      # uwu-phone. Scoped to wt0 only on purpose: do NOT add 853 to
      # eth0 (direct-link) — the firewall would let any desktop on
      # the LAN bypass the local resolv.conf and talk DoT directly
      # to AdGuard, which is fine for the phone but unnecessary for
      # UwU (it already has plaintext :53 and prefers local caching
      # for that path). eno1 (public) also doesn't get 853 — DoT is
      # mesh-only.
      networking.firewall.interfaces.wt0 = {
        allowedTCPPorts = lib.mkAfter [
          53
          3000
          853
        ];
        allowedUDPPorts = lib.mkAfter [ 53 ];
      };
    }
  ;
}