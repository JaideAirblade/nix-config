# Import-only entry for TSBW-W01800 hardware-specific config.
{ ... }:

{
  imports = [
    ./luks.nix
    ./thunderbolt.nix
    ./graphics.nix
  ];
}