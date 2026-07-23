# Import-only entry for Windows server tools.
{ ... }:

{
  imports = [
    ./windows-tools.nix
  ];
}