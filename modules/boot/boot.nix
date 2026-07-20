# Bootloader + boot settings.
#
# Shared bits (systemd-boot, EFI) live here. Host-specific bits (zram,
# fstrim, gc, kernelPackages) are written with lib.mkDefault so a host
# can override them — e.g. TSBW-W01800 sets its own kernelPackages and
# skips zram since it has a real swap partition.
{ lib, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Limit boot entries to keep the EFI menu manageable.
  boot.loader.systemd-boot.configurationLimit = 10;

  # Compressed RAM swap — safety net without wearing the SSD.
  # UwU uses this; TSBW-W01800 has a real LUKS swap partition and sets
  # zramSwap.enable = lib.mkForce false in its host config.
  zramSwap = {
    enable = lib.mkDefault true;
    algorithm = lib.mkDefault "zstd";
  };

  # Periodic SSD trim. Useful on any host with SSD storage; a host with
  # only spinning rust can disable this via mkForce.
  services.fstrim.enable = lib.mkDefault true;

  # Disk-usage hygiene (from the guide's "Reducing Disk Usage").
  nix.gc = {
    automatic = lib.mkDefault true;
    dates = lib.mkDefault "weekly";
    options = lib.mkDefault "--delete-older-than 7d";
  };
  nix.settings.auto-optimise-store = lib.mkDefault true;
}