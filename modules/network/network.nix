# Networking.
{ ... }:

{
  networking.hostName = "UwU"; # must match the nixosConfigurations key in flake.nix
  networking.networkmanager.enable = true;
}