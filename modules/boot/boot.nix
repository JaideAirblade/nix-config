# Bootloader, zram swap, and Nix garbage collection.
{ ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Limit boot entries to keep the EFI menu manageable.
  boot.loader.systemd-boot.configurationLimit = 10;

  # Compressed RAM swap — safety net without wearing the SSD.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  # Disk-usage hygiene (from the guide's "Reducing Disk Usage").
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  nix.settings.auto-optimise-store = true;
}