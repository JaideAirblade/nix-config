# Graphics: NVIDIA proprietary drivers (RTX 3080 / GA102) + latest kernel.
#
# The card was previously running nouveau, which lacks proper DP audio routing
# and reclocking for this GPU. Proprietary nvidia_x11 (595.x) supports the
# kernel in linuxPackages_latest (7.1.x).
#
# Modesetting backend (not the legacy X11 driver) is used because the session
# is Wayland (Mango compositor via DankGreeter). The nvidia_drm.modeset=1 kernel
# parameter is required for Wayland.
{ config, pkgs, ... }:

{
  # Latest mainline kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Enable nvidia-drm modesetting (needed for Wayland).
  boot.kernelParams = [ "nvidia-drm.modeset=1" "nvidia-drm.fbdev=1" ];

  # Blacklist nouveau so it can't grab the card.
  boot.blacklistedKernelModules = [ "nouveau" ];

  # Load nvidia modules early (before display manager) so the GPU is ready.
  boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_drm" "nvidia_uvm" ];

  hardware.graphics.enable = true;
  # 32-bit graphics drivers — required by Steam + Proton for 32-bit titles
  # and by wineWow64. Enable32Bit must live alongside `enable` here so we
  # don't split the graphics config across two modules.
  hardware.graphics.enable32Bit = true;

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Closed-source driver.
    open = false;

    # Wayland + KMS: use modesetting, not the legacy X11 driver.
    modesetting.enable = true;

    # Let nvidia-uvm create /dev/nvidia-uvm (needed by CUDA / compute).
    package = config.boot.kernelPackages.nvidia_x11;

    # Don't let NixOS manage the prime/offload bits; single-GPU, display attached.
    powerManagement.enable = true;
    powerManagement.finegrained = false;
  };

  # WLR_DRM_NO_ATOMIC=1 — required by wlroots compositors (Mango) on NVIDIA
  # to enable tearing (bypassing VSync for fullscreen games). Without this,
  # tearing page flips are rejected by nvidia-drm's atomic commit path.
  # Set in the session environment so greetd passes it to mango at startup.
  environment.sessionVariables.WLR_DRM_NO_ATOMIC = "1";
}