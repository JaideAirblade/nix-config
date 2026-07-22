# Virtual camera (v4l2loopback) for real-time face swap / deepfake webcam.
#
# This module loads the v4l2loopback kernel module, which creates a virtual
# /dev/videoN device that programs can write frames to and browsers/apps
# can read as if it were a real webcam. This is the infrastructure layer
# for Deep-Live-Cam, FaceFusion, and similar tools that need to pipe
# processed face-swap video into a browser for age verification, video
# calls, etc.
#
# The actual face swap tools (Deep-Live-Cam etc.) are NOT installed
# system-wide — they're run from a venv in ~/projects/ because they need
# specific Python versions + onnxruntime-gpu + CUDA that are easier to
# manage outside NixOS's package set.
#
# BROWSER NOTE: Firefox has a known bug where it cannot detect v4l2loopback
# virtual cameras (Red Hat bug #2412269). Use Chromium for any web-based
# camera flow (age verification, etc.).
{ config, lib, pkgs, ... }:

{
  # v4l2loopback kernel module — creates virtual video device(s).
  # exclusive_caps=1 makes the device advertise capabilities only when a
  # producer is actively writing, which helps some picky apps detect it.
  boot.extraModulePackages = [
    config.boot.kernelPackages.v4l2loopback
  ];

  # Load at boot. We want the virtual camera ready at all times.
  boot.kernelModules = [ "v4l2loopback" ];

  # Module parameters:
  #   video_nr=10  — claim /dev/video10 specifically (avoids clashing with
  #                  real webcams which usually get /dev/video0..4)
  #   exclusive_caps=1 — only advertise V4L2_CAP_STREAMING when a writer is
  #                      attached (helps Chromium detect it as a real camera)
  #   card_label="DeepLiveCam" — shows up in apps as this name
  boot.extraModprobeConfig = ''
    options v4l2loopback video_nr=10 exclusive_caps=1 card_label="DeepLiveCam"
  '';

  # System-level packages that the face swap tools depend on but are
  # useful to have globally too.
  environment.systemPackages = with pkgs; [
    v4l-utils   # v4l2-ctl — inspect/control virtual and real cameras
    python311   # Deep-Live-Cam (works with 3.11+; 3.10 is EOL in nixpkgs-unstable)
  ];

  # NixOS defaults extraOutputsToInstall to ["man" "info" "doc"], which
  # forces building python311's doc output. That fails on current
  # nixpkgs-unstable due to a docutils 0.22.4 regression (nixpkgs #499166).
  # Dropping "doc" from the extra outputs skips the broken derivation.
  # Restore to ["man" "info" "doc"] once nixpkgs #499166 is fixed.
  environment.extraOutputsToInstall = lib.mkForce [ "man" "info" ];
}