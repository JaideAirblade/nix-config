# Import-only entry for TSBW-W01800 services.
{ ... }:

{
  imports = [
    ./printing.nix
    ./scanning.nix
    ./steam.nix
    ./upower.nix
    ./gvfs.nix
    ./power.nix           # battery life optimization (PPD stays, adds ASPM/Wi-Fi powersave)
    ./battery-services.nix # geoclue disabled, dnsproxy stopped on battery
  ];
}