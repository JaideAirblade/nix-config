# Import-only entry for TSBW-W01800 packages.
{ ... }:

{
  imports = [
    ./system-packages.nix
    ../../../modules/packages/network-tools
    ../../../modules/packages/media
    ./games.nix
    ./webbrowsers.nix
    ./disk-recovery.nix
    ./archives.nix
    ./work
  ];
}