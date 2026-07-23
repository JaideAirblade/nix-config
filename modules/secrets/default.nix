# Import-only entry for the secrets module.
# Owns declarative secrets management via sops-nix + age.
{ ... }:

{
  imports = [
    ./secrets.nix
  ];
}