# UwU host-specific networking — sets the hostname.
# The shared modules/network/network.nix handles NetworkManager + IVPN.
{ pkgs, ... }:

{
  networking.hostName = "UwU"; # must match the nixosConfigurations key in flake.nix

  # --- Shattered Empire (BnS private server) — disable delayed ACK ---------
  # The game client (Client.exe via Heroic/Proton) does not set TCP_NODELAY
  # or TCP_QUICKACK on its sockets. The Linux kernel then delays ACKs by up
  # to 40ms (the ato timer), adding 40ms of artificial latency to every
  # server packet that arrives without a follow-up within 40ms.
  #
  # The ip route `quickack 1` flag tells the kernel to ACK immediately on
  # all TCP connections to this IP, eliminating the 40ms penalty without
  # needing LD_PRELOAD (which pressure-vessel strips anyway) or patching
  # the game binary.
  #
  # Measured: ACK latency max dropped from 40.3ms to 0.03ms.
  # Server IP: 148.251.13.54 (Hetzner, DE) — SEBNS private server.
  networking.localCommands = ''
    ${pkgs.iproute2}/bin/ip route add 148.251.13.54/32 via 192.168.178.1 dev enp10s0 quickack 1 2>/dev/null || true
  '';
}