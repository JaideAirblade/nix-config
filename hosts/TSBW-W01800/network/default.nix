# Import-only entry for TSBW-W01800 network config.
{ ... }:

{
  imports = [
    ./network.nix
    ./dns.nix
  ];
}