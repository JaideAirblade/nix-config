# Import-only entry for TSBW-W01800 services.
{ ... }:

{
  imports = [
    ./printing.nix
    ./scanning.nix
    ./steam.nix
    ./upower.nix
    ./gvfs.nix
  ];
}