# Import-only entry for the packages module.
#
# `packages.nix` holds general CLI/utility tools that don't fit a more
# specific category. Subfolders group related GUI apps by category.
{ ... }:

{
  imports = [
    ./packages.nix
    ./terminal
    ./file-manager
  ];
}