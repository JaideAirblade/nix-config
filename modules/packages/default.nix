# Import-only entry for the packages module.
#
# Only the base packages.nix is imported here — it has the universal CLI
# tools + terminals every host wants. Subfolders (file-manager, media,
# onepassword, network-tools, terminal) are imported by each host
# directly from hosts/<name>/packages/default.nix, so a host pulls only
# what it actually uses.
{ ... }:

{
  imports = [
    ./packages.nix
  ];
}