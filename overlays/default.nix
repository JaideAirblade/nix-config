# Overlays for custom packages.
#
# `additions` exposes the packages defined in ../pkgs/ as part of pkgs,
# so hosts can reference `pkgs.betterbird` and `pkgs.octarine` directly
# in environment.systemPackages without a separate callPackage site.
#
# The Millennium overlay (overlays/millennium.nix) takes a flake input
# argument, so it's NOT a standard overlay and is NOT exported here.
# Hosts apply it inline:
#   { nixpkgs.overlays = [ (import ../../overlays/millennium.nix { millennium-input = inputs.millennium; }) ]; }
{
  # Expose custom packages from pkgs/ as part of pkgs
  additions = final: _prev: import ../pkgs final;

  # Temporary compatibility fixes for Python packages used by OSINT and
  # Windows administration tools. Applied explicitly by the relevant hosts.
  python-package-fixes = import ./python-package-fixes.nix;

  # Enable Wi-Fi Display (Miracast/WFD) support in wpa_supplicant.
  # nixpkgs omits CONFIG_WIFI_DISPLAY=y, which prevents NetworkManager
  # from relaying P2P peers to gnome-network-displays.
  wpa-supplicant-wifi-display = import ./wpa-supplicant-wifi-display.nix;
}
