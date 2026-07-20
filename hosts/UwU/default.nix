# Per-host entry for "UwU" — Jaide's personal AMD laptop.
#
# Imports the shared module tree (../../modules) plus host-specific
# modules that were split out of the shared tree because they only apply
# to this host's hardware/usage:
#   graphics  — NVIDIA RTX 3080 proprietary driver, latest kernel
#   gaming    — Steam + Proton + Heroic + Wine + MangoHud + gamescope
#   macrotool — Tauri v2 macro app runtime deps + udev rules
#   devices   — YubiKey + Scyrox keyboard/mouse udev rules
#   packages  — UwU-only GUI apps (Discord+Equicord, Seanime, Geary, etc.)
#
# The host-specific network.nix sets the hostname; shell.nix overrides the
# rebuild alias to target .#UwU.
{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./state.nix
    ../../modules

    # Host-specific modules
    ./graphics
    ./gaming
    ./macrotool
    ./devices
    ./packages
    ./network
    ./shell
    ./users
  ];
}