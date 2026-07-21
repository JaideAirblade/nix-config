# TSBW-W01800 host-specific networking — sets the hostname.
{ ... }:

{
  networking.hostName = "TSBW-W01800"; # must match the nixosConfigurations key in flake.nix

  # NetworkManager enables ModemManager by default (mkDefault true), but
  # this laptop has no cellular modem. Disable it to avoid an unnecessary
  # always-running D-Bus daemon. If a modem is ever connected, D-Bus
  # activation can still start it on demand.
  networking.modemmanager.enable = false;
}