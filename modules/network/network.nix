# Networking.
{ ... }:

{
  networking.hostName = "Uwu"; # must match the nixosConfigurations key in flake.nix
  networking.networkmanager.enable = true;
}