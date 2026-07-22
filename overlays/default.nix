# Overlays for custom packages.
#
# `additions` exposes the packages defined in ../pkgs/ as part of pkgs,
# so hosts can reference `pkgs.betterbird` and `pkgs.octarine` directly
# in environment.systemPackages without a separate callPackage site.
{
  # Expose custom packages from pkgs/ as part of pkgs
  additions = final: _prev: import ../pkgs final;

  # Millennium overlay — applies upstream Millennium overlay + fixes
  # pkgsi686Linux.minizip-ng test failures in the Nix sandbox.
  # Pass the millennium flake input so it can reference overlays.default.
  millennium = import ./millennium.nix;
}