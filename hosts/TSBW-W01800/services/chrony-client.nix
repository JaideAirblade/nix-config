# Opt in to chrony-client — syncs this host's clock via NTS to
# Luna-Server (time.jaidechan.moe) over the NetBird mesh.
#
# Why we want this on TSBW specifically: the office LAN firewall
# (OPNsense HA pair) drops inbound UDP return traffic, so the in-the-
# clear NTP/123 polling that systemd-timesyncd does never gets a
# reply. Verified in the 2026-08-13 place.pcapng capture on this host:
# 74 distinct outbound NTP/123 flows over 84 min, 0 inbound;
# `System clock synchronized: no`. The NTS path (TCP/4460 to the mesh,
# then authenticated UDP/123) gets us a working clock without poking
# the office firewall.
#
# Server side: hosts/Luna-Server/server/chrony.nix.
#
# Why this is host-specific (not a shared `modules/` feature):
# the dendritic walker imports `modules/X.nix` as flake-parts modules
# with no `pkgs` arg, but a chrony service config needs `pkgs.chrony`.
# `nixos.hosts.<X>` slots are NixOS modules that DO get `pkgs`, so the
# config lives here and other hosts that want to opt in can copy this
# file (or we promote it to a shared module once a second host needs
# it).
_:

let
  serverFqdn = "time.jaidechan.moe";
in
{
  nixos.hosts."TSBW-W01800" =
    { lib, pkgs, ... }:
    {
      # timesyncd off. The chrony module asserts on this; making it
      # explicit documents intent.
      services.timesyncd.enable = false;

      services.chrony = {
        enable = true;
        package = pkgs.chrony;

        # NTS-KE + NTP pointing at Luna-Server. The NTS path means a
        # mangling firewall can't silently corrupt the time stream --
        # either the client authenticates the response or it ignores it.
        servers = [
          # The mesh DNS should resolve this to Luna-Server's NetBird IP
          # (100.77.228.137) automatically. The `iburst` option sends
          # eight packets on first connect instead of one, which is
          # what we want for a client that was just rebooted.
          "${serverFqdn} iburst nts"
        ];

        # First-boot step. A TSBW that was off for a week is going to be
        # way off; we want the first reply to set the clock, not slew
        # it back at 0.5ppm. Three steps of 100ms-or-greater is plenty
        # for "catch up on boot" without overstepping on a running
        # system.
        makestep = {
          enable = true;
          threshold = 0.1;
          limit = 3;
        };
      };

      # No firewall rule needed. chrony is a pure client here; it
      # initiates outgoing connections, the kernel's stateful firewall
      # allows return traffic for established connections. The
      # authenticated UDP/123 packets from the server are tiny and
      # well-spaced (chrony starts at 32s polls, doubles to 1024s when
      # stable), so the firewall's "established" rule covers them.
    };
}
