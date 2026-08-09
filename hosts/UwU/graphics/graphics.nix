# Graphics: NVIDIA proprietary drivers (RTX 3080 / GA102) + latest kernel.
#
# The card was previously running nouveau, which lacks proper DP audio routing
# and reclocking for this GPU. Proprietary nvidia_x11 (595.x) supports the
# kernel in linuxPackages_latest (7.1.x).
#
# Modesetting backend (not the legacy X11 driver) is used because the session
# is Wayland (Mango compositor via DankGreeter). The nvidia_drm.modeset=1 kernel
# parameter is required for Wayland.
_:
{
  nixos.hosts."UwU" =
    { config, pkgs, ... }:

    {
      # Latest mainline kernel.
      boot.kernelPackages = pkgs.linuxPackages_latest;

      # ath12k fw_stats bypass: WCN7850 firmware never responds to stats requests,
      # causing hw_mutex to be held for 4 seconds (completion timeouts). This blocks
      # EAPOL frame TX during WPA2 GTK rekey → AP sends PREV_AUTH_NOT_VALID →
      # WiFi disconnects every 10 minutes (FRITZ!Box default rekey interval).
      # Patch makes ath12k_mac_get_fw_stats() return -EOPNOTSUPP immediately,
      # before acquiring hw_mutex. Trade-off: wifi stats/txpower via fw_stats
      # won't work, but the connection stays stable.
      boot.kernelPatches = [
        {
          name = "ath12k-fw-stats-bypass";
          patch = ../../../patches/ath12k-fw-stats-bypass.patch;
        }
      ];

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
      # NVIDIA-specific compositor env vars were historically set here
      # (WLR_DRM_NO_ATOMIC=1 for wlroots compositors). Niri is built on
      # Smithay and uses DRM/KMS directly — it does NOT need that hint,
      # and the host override at hosts/UwU/desktop/noctalia-host.nix
      # forces WLR_DRM_NO_ATOMIC to empty. The kernel param
      # `nvidia-drm.modeset=1` above remains the canonical NVIDIA-on-
      # Wayland prerequisite and is required by both Mango and Niri.
    }
  ;
}
