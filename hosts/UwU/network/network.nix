# UwU host-specific networking — sets the hostname.
# The shared modules/network/network.nix handles NetworkManager + IVPN.
_:
{
  nixos.hosts."UwU" =
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

      # Disable Energy Efficient Ethernet on the Realtek wired adapter.
      # EEE can silently break long-lived Discord voice/WebRTC sessions while
      # ordinary TCP traffic continues to look healthy. Apply it once at boot
      # and again whenever NetworkManager brings the interface back up.
      systemd.services.disable-eee-enp10s0 = {
        description = "Disable EEE on the Realtek Ethernet adapter";
        wantedBy = [ "multi-user.target" ];
        wants = [ "sys-subsystem-net-devices-enp10s0.device" ];
        after = [
          "NetworkManager.service"
          "sys-subsystem-net-devices-enp10s0.device"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.ethtool}/bin/ethtool --set-eee enp10s0 eee off";
          RemainAfterExit = true;
        };
      };

      environment.etc."NetworkManager/dispatcher.d/20-disable-eee-enp10s0" = {
        mode = "0755";
        text = ''
          # Keep EEE disabled after NetworkManager reconnects the link.
          [ "$1" = "enp10s0" ] || exit 0
          [ "$2" = "up" ] || exit 0
          ${pkgs.ethtool}/bin/ethtool --set-eee "$1" eee off >/dev/null 2>&1 || true
        '';
      };
    }
  ;
}
