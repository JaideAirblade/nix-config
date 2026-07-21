# Niri — scrollable tiling Wayland compositor
# https://github.com/YaLTeR/niri
# Using niri-flake which provides both NixOS and home-manager modules
#
# Niri is the SECONDARY compositor on this host (mango is primary).
# It stays installed so it can be selected at the DMS greeter.
{inputs, pkgs, ...}: {
  imports = [
    inputs.niri.nixosModules.niri
  ];

  # Required by DMS greeter assertion — compositor must be enabled at NixOS level
  # Use niri-unstable (26.04+) — needed for `include` directives and `recent-windows`
  # block that DMS config templates rely on. Stable (25.08) lacks these features.
  programs.niri.enable = true;
  programs.niri.package = inputs.niri.packages.x86_64-linux.niri-unstable;

  # XWayland support — niri auto-detects xwayland-satellite if it's in PATH.
  # niri-flake does NOT install it automatically; it must be added explicitly.
  # This is required for Steam and other X11 apps to work.
  environment.systemPackages = with pkgs; [
    xwayland-satellite
  ];
}