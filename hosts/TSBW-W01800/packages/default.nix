# Import-only entry for TSBW-W01800 packages.
{ ... }:

{
  imports = [
    ./system-packages.nix
    ../../../modules/packages/network-tools
    ../../../modules/packages/media
    ../../../modules/packages/onepassword
    ./games.nix
    ./webbrowsers.nix
    ./disk-recovery.nix
    ./archives.nix
    ./work
  ];
}