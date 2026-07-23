# Import-only entry for security modules.
{ ... }:

{
  imports = [
    ./security.nix
  ];
}