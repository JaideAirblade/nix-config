# UwU-Server host-specific networking — sets the hostname.
# The shared modules/network/network.nix handles NetworkManager.
#
# Interfaces (from the live ISO):
#   eno1 / enp195s0  — Aquantia AQC113 10Gbase-T (primary, wired to the LAN)
#   wlp194s0         — Intel AX200 WiFi
# UwU's SEBNS quickack route and Realtek EEE workaround are NOT carried over:
# this box has different NICs and no such requirements yet.
_:
{
  nixos.hosts."UwU-Server" =
    _:

    {
      networking.hostName = "UwU-Server"; # must match the nixosConfigurations key in flake.nix
    }
  ;
}
