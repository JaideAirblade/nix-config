# Per-host entry for "TSBW-W01800" — Jaide's work laptop.
#
# AMD, LUKS-encrypted root + swap, Thunderbolt dock, YubiKey.
# Uses niri as the primary compositor (with mango as secondary) and
# DankCalendar alongside DMS. No home-manager — per-user dotfiles stay
# writable, matching the convention used across this flake.
{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./state.nix
    ../../modules

    # Host-specific modules
    ./hardware
    ./security
    ./boot
    ./network
    ./services
    ./desktop
    ./packages
    ./users
    ./shell
  ];
}