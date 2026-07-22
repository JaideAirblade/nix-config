# Import-only entry for the firewall module.
{ ... }:

{
  imports = [ ./firewall.nix ];
}