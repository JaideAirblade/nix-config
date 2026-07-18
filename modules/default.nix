# Aggregates all system modules. Import-only.
# Each subfolder has its own default.nix (imports only) + a config file.
{ ... }:

{
  imports = [
    ./boot
    ./nix
    ./network
    ./locale
    ./users
    ./audio
    ./printing
    ./packages
    ./shell
    ./bluetooth
    ./wm
  ];
}