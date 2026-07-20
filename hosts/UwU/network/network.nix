# UwU host-specific networking — sets the hostname.
# The shared modules/network/network.nix handles NetworkManager + IVPN.
{ ... }:

{
  networking.hostName = "UwU"; # must match the nixosConfigurations key in flake.nix
}