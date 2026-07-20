# Graphics: AMD APU/iGPU (work laptop has no discrete NVIDIA GPU).
#
# Uses the in-tree amdgpu driver (loaded automatically by default-kernel
# NixOS, no proprietary driver needed). We only enable hardware.graphics
# + 32-bit for Steam/Proton, and pull linuxPackages_latest (the work
# config previously pinned it for amdgpu fixes).
{ pkgs, lib, ... }:

{
  # Latest kernel — matches the work config's previous setting.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

  hardware.graphics.enable = true;
  # 32-bit graphics — required by Steam + Proton for 32-bit titles
  # and by wineWow64.
  hardware.graphics.enable32Bit = true;

  # amdgpu is loaded automatically; no service.xserver.videoDrivers
  # entry needed for the in-tree driver under Wayland.
}