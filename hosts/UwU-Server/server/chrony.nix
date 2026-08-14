# Chrony NTP + NTS server on UwU-Server.
#
# Why this exists: the office LAN firewall (OPNsense HA pair) drops inbound
# UDP return traffic, so the in-the-clear NTP/123 polling that
# `services.timesyncd` does from TSBW never gets a reply. Verified in the
# 2026-08-13 place.pcapng capture: 74 distinct outbound NTP/123 flows
# over 84 minutes, 0 inbound; `timedatectl` on TSBW reports
# `System clock synchronized: no`.
#
# Pulling time over the NetBird mesh + NTS (Network Time Security) sidesteps
# the firewall: the NTS-KE handshake runs over TCP/4460 (which the firewall
# tolerates because it's TLS-like, or routes over the relay), and once
# established, the per-packet authentication in the NTPv4 stream means a
# mangling firewall can no longer silently corrupt the time.
#
# Stratum: 2. UwU-Server syncs upstream to the public pool; clients on the
# mesh sync to UwU-Server. (Stratum-1 would need a hardware ref like a
# GPS/PPS; the chrony refclock block at the bottom of `extraConfig` is
# commented as a "wire-up when GPS arrives" hook, no other code change
# needed.)
#
# What this exposes:
#   * UDP/123  NTP    on the NetBird IP (100.77.228.137) and the direct-link
#                    (10.10.0.1), and 127.0.0.1
#   * TCP/4460 NTS-KE on the same three interfaces
# What this does NOT expose:
#   * Public internet. No firewall rule on eno1, so nobody outside the
#     mesh can reach it. This is intentional: we don't want to be a public
#     NTP server, and we don't want random scanners hitting the NTS-KE.
#
# Client config (TSBW, etc.) lives in
# hosts/TSBW-W01800/services/chrony-client.nix and is opt-in per host.
#
# Outer arg list (`_:`) is the flake-parts / dendritic walker signature:
# no `pkgs` here, because walker-imported modules don't get it. Inner
# `nixos.hosts."UwU-Server" = { pkgs, lib, ... }:` is the NixOS module
# that DOES get `pkgs` from the standard module system. Same pattern as
# hosts/UwU-Server/network/direct-link.nix and hosts/UwU-Server/boot-order.nix.
_:

let
  # Address UwU-Server advertises itself as on each interface the clients
  # reach it from. These come from:
  #   * netbirdMesh (modules/network/netbird-mesh.nix)         -> 100.77.228.137
  #   * direct-link (hosts/UwU-Server/network/direct-link.nix) -> 10.10.0.1
  # We hardcode the IPs (not interface names) because chrony's
  # `bindaddress` directive takes a literal address. If either rotates on
  # re-enrollment, update both this list AND the regression test.
  nbIP = "100.77.228.137";
  linkIP = "10.10.0.1";

  # An NTS server needs a TLS cert+key. We piggyback on the *.jaidechan.moe
  # wildcard cert that nginx already has from lego+certbot — chrony
  # re-reads the files on SIGHUP so a cert renewal Just Works, no
  # service restart needed. (The wildcard is mesh-only; see
  # hosts/UwU-Server/server/dashboard.nix for the lego setup.)
  domain = "jaidechan.moe";
  fqdn = "time.${domain}";
  certPath = "/var/lib/acme/${domain}/fullchain.pem";
  keyPath = "/var/lib/acme/${domain}/key.pem";
in
{
  nixos.hosts."UwU-Server" =
    { pkgs, lib, ... }:
    {
      # Disable timesyncd. The chrony module asserts on this anyway, but
      # being explicit makes the intent obvious in the built config.
      services.timesyncd.enable = false;

      # The NTS server reads the *.jaidechan.moe cert + key, which the
      # acme module writes 0640 owned by acme:nginx. chrony runs as the
      # `chrony` user, so we make `chrony` a supplementary member of
      # the `nginx` group. The cert is world-readable for the
      # `fullchain.pem` (public cert, fine); the `key.pem` is mode
      # 0640 root:nginx, so group read is required.
      users.users.chrony.extraGroups = [ "nginx" ];

      # When lego renews the wildcard cert, the existing acme
      # postRun in dashboard.nix already restarts nginx and
      # adguardhome. We extend that list with chrony so the NTS
      # server picks up the new cert without manual intervention.
      # (NixOS list options merge across modules by default, so
      # appending here doesn't conflict with the existing entries.)
      security.acme.certs.${domain}.reloadServices =
        [ "chrony.service" ];

      services.chrony = {
        enable = true;
        # NOTE: enableNTS is deliberately FALSE even though we run an
        # NTS-KE *server*. The nixpkgs module's enableNTS option appends
        # `nts` to every upstream server/pool line AND sets
        # ntsservercert/ntsserverkey/ntstrustedcerts from its own
        # tlsCertFile/tlsKeyFile options. Our NTS server directives are
        # written manually in extraConfig below, so the option would
        # double-configure the server side and force NTS on the upstream
        # pool (most pool.ntp.org servers don't speak NTS — the server
        # stayed stratum 0 for hours because of exactly that).
        # Upstream sync is plain authenticated-by-nothing UDP/123, which
        # is the same trust level as every default NixOS install; the
        # NTS value is on the mesh CLIENT side (TSBW etc.), which
        # authenticates OUR server.
        # enableNTS = false;
        # Use the nixpkgs package directly; no overlay needed for chrony
        # 4.8, it's stable.
        package = pkgs.chrony;

        # Upstream sources. The default `config.networking.timeServers` is
        # fine (it pulls from the systemd-timesyncd default list, mostly
        # NTP pool), but we set it explicitly so this is self-documenting
        # and doesn't change if someone flips `networking.timeServers`.
        servers = [
          "0.pool.ntp.org iburst"
          "1.pool.ntp.org iburst"
          "2.pool.ntp.org iburst"
          "3.pool.ntp.org iburst"
        ];

        # On a server that was just deployed or just woke up from a clock
        # that's been wrong for days (which describes TSBW right now), the
        # first offset can be huge. `makestep 0.1 3` steps the clock up
        # to three times if it's off by more than 100ms. After that,
        # chrony only slews, which is correct for a running system.
        makestep = {
          enable = true;
          threshold = 0.1;
          limit = 3;
        };

        extraConfig = ''
          # --- Bind to mesh-only addresses ----------------------------
          # Chrony default is INADDR_ANY. We restrict to localhost, the
          # NetBird IP, and the direct-link IP. Anything else is
          # unreachable. (The firewall layer is the belt to this
          # suspenders; both are needed in case someone ever disables
          # the nftables rules while debugging.)
          bindaddress ${linkIP}
          bindaddress ${nbIP}

          # --- NTS server cert + key ---------------------------------
          # NTS-KE (TCP/4460) presents this cert to clients. Clients
          # verify it against the *.jaidechan.moe chain. Because the
          # cert is mesh-only, a client outside the mesh can't
          # complete the NTS-KE anyway, but this layer is
          # defense-in-depth.
          ntsservercert ${certPath}
          ntsserverkey ${keyPath}
          ntstrustedcerts ${certPath}

          # --- Server-side hardening ----------------------------------
          # The trust model here is "NTS clients get authenticated time,
          # plain clients get unauthenticated time." If we ever wanted
          # to *require* NTS, the right knob is firewall-level: close
          # UDP/123 entirely and force everyone through NTS-KE. Not
          # doing that now because some clients -- like systemd's
          # ntpdate fallback -- don't speak NTS yet.

          # --- (Hook for GPS refclock) -------------------------------
          # Wire-up when a PPS-capable GPS receiver is attached:
          #   refclock SHM 0 refid GPS precision 1e-3 noselect
          #   refclock PPS /dev/pps0 refid PPS precision 1e-7 lock GPS
          # Commented out so the server stays a stratum-2 (syncs
          # upstream, serves the mesh) until GPS hardware is added.
        '';
      };

      # --- Firewall: open NTP + NTS-KE on mesh and direct-link only ---
      # The chrony NixOS module does NOT add any firewall rules; we do.
      # This is the trust boundary: even if a future `bindaddress` change
      # is forgotten, the firewall keeps the public side closed.
      #
      # `networking.firewall.interfaces.${iface}.allowedTCPPorts` is
      # interface-scoped, so the rule only takes effect for traffic
      # arriving on that interface -- not for traffic on eno1 (public).
      networking.firewall.interfaces."wt0".allowedTCPPorts = [
        123    # NTP (some NTS-KE clients use TCP, not just UDP)
        4460   # NTS-KE
      ];
      networking.firewall.interfaces."wt0".allowedUDPPorts = [
        123    # NTP
      ];
      networking.firewall.interfaces."eth0".allowedTCPPorts = [
        123
        4460
      ];
      networking.firewall.interfaces."eth0".allowedUDPPorts = [
        123
      ];
    };
}
