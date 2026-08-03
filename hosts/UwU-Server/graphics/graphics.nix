# Graphics: AMD Radeon 890M (Strix / gfx1150, RDNA 3.5) — integrated into the
# Ryzen AI 9 HX 470. Fully open stack: amdgpu kernel driver + RADV (Vulkan) +
# radeonsi (OpenGL) via Mesa. No proprietary driver, no extra session
# variables — unlike UwU's NVIDIA setup, wlroots (Mango) needs no
# WLR_DRM_NO_ATOMIC workaround here.
#
# linuxPackages_latest is used because Strix is still relatively new silicon;
# the latest kernel carries the freshest amdgpu DCN fixes and the amd_pstate
# improvements for HX 470.
_:
{
  nixos.hosts."UwU-Server" =
    { pkgs, ... }:

    {
      # Latest mainline kernel (7.1.x at the time of writing).
      boot.kernelPackages = pkgs.linuxPackages_latest;

      # Load amdgpu early so the console + greeter get KMS from the start.
      boot.initrd.kernelModules = [ "amdgpu" ];

      hardware.graphics.enable = true;
      # 32-bit graphics drivers — required by Steam + Proton for 32-bit titles
      # and by wineWow64.
      hardware.graphics.enable32Bit = true;
    }
  ;
}
