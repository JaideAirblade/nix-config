# NVIDIA GTX 750 Ti — legacy driver (535xx branch, Kepler architecture).
# The 750 Ti uses the GK106/GK107 GPU (Kepler), which is only supported
# by the legacy 535 driver branch. Newer drivers (565+) dropped Kepler.
#
# This is the same structure as UwU's graphics.nix but with the legacy
# driver and no 32-bit gaming support (no Steam/Proton on this host).
{ pkgs, config, ... }:

{
  # Legacy NVIDIA driver for Kepler GPUs (GTX 600/700 series)
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;
  };

  # Use the legacy 535 driver branch (last to support Kepler)
  hardware.nvidia = {
    modesetting.enable = true;
    open = false;  # Kepler doesn't support open kernel modules
    package = config.boot.kernelPackages.nvidiaPackages.legacy_535;
  };

  # Load NVIDIA kernel module
  boot.kernelModules = [ "nvidia" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.nvidiaPackages.legacy_535.out ];
}