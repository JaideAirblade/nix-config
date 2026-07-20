# TSBW-W01800 host-specific networking — sets the hostname.
{ ... }:

{
  networking.hostName = "TSBW-W01800"; # must match the nixosConfigurations key in flake.nix
}