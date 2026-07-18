# Per-host entry for "Uwu". Import-only.
# Host-specific overrides live in sibling files imported here.
{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./state.nix
    ../../modules
  ];
}