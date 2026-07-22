# Overlay for Millennium — Steam skin/theme loader.
#
# Millennium's official flake pins its own nixpkgs internally, so overlays
# on the host's nixpkgs don't reach its build. Instead, we call the
# Millennium package expressions (millennium.nix + steam.nix) directly from
# the flake source with our own pkgs, where we CAN override
# pkgsi686Linux.minizip-ng to skip its test suite (which fails in the sandbox).
#
# We fetch millennium-src ourselves via fetchFromGitHub with the same rev
# the flake pins.
{ millennium-input }:

final: _prev: let
  # Import the Millennium package Nix expressions from the flake source.
  # millennium-input is the flake output, and its source tree lives at
  # the flake's outPath under packages/nix/.
  srcStr = builtins.toString millennium-input;

  # The Millennium C++/TS source, pinned by the flake to a specific rev.
  # We fetch it ourselves so we control the nixpkgs instance.
  millennium-src = final.fetchFromGitHub {
    owner = "SteamClientHomebrew";
    repo = "Millennium";
    rev = "f37f05bdbd4727d873a1ad83ce72d062ef9a0c48";
    hash = "sha256-MJLJ0I48HXgfOpISTAbDMYMUdWj9A6M+jGQz4uAvwyw=";
  };

  # Our pkgsi686Linux with minizip-ng tests disabled (sandbox test failures).
  pkgsi686LinuxFixed = final.pkgsi686Linux.extend (iFinal: iPrev: {
    minizip-ng = iPrev.minizip-ng.overrideAttrs {
      doCheck = false;
    };
  });

  # Build Millennium using the flake's own millennium.nix expression,
  # but with our fixed pkgsi686Linux.
  millennium = final.callPackage "${srcStr}/millennium.nix" {
    inherit millennium-src;
    pkgsi686Linux = pkgsi686LinuxFixed;
  };

  # Wrap Steam with Millennium using the flake's steam.nix expression.
  millennium-steam = final.callPackage "${srcStr}/steam.nix" {
    inherit millennium;
  };
in {
  inherit millennium-steam;
}