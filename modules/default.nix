# Aggregates all system modules. Import-only.
# Each subfolder has its own default.nix (imports only) + a config file.
{ ... }:

{
  imports = [
    ./boot
    ./nix
    ./network
    ./firewall
    ./security
    ./locale
    ./users
    ./audio
    ./printing
    ./packages
    ./shell
    ./bluetooth
    ./theming
    ./fonts
    ./firmware
    ./keyring
    ./wm
    ./ai
    ./cloud
    ./facemask
    ./metadata
    ./secrets
  ];
}