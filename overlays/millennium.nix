# Overlay for Millennium — Steam skin/theme loader.
#
# Millennium ships its own Nix expressions via flake input
# `inputs.millennium` (a flake that packages the C++/TS source against
# the flake's own nixpkgs). Re-export the upstream `millennium-steam`
# as `pkgs.millennium-steam` so host modules can use it without needing
# to know about flake inputs.
#
# Why no callPackage: previously this overlay used callPackage to
# `inputs.millennium.packages.<system>` so we could host-fix
# pkgsi686Linux.minizip-ng (doCheck=false; sandbox test failures).
# That pattern broke on 2026-08-20 because pinning a hardcoded
# `millennium-src` rev here drifted from the flake's own
# `millennium-src` input (the upstream restructured patch_engine/ into
# loopback/, the Nix expr here was no longer the right shape for the
# pinned src). Per the user's rule "nix flake update should always
# work", just delegate to the flake's pre-built packages: any future
# flake update bumps inputs.millennium which brings the new src + the
# fixed Nix expr together.
#
# minizip-ng note: with the upstream-flake delegation, the minizip-ng
# test issue (if it returns) will be fixed in the upstream flake's
# nixpkgs instance, not here. Track at
# https://github.com/SteamClientHomebrew/Millennium if regressions
# show up.
{ millennium-input }:

final: _prev:
let
  sys = final.stdenv.hostPlatform.system;
  millennium-pkgs = millennium-input.packages.${sys} or {};
in
{
  millennium-steam =
    if millennium-pkgs ? millennium-steam
    then millennium-pkgs.millennium-steam
    else throw "millennium flake input does not expose 'millennium-steam' for system ${sys}; check that inputs.millennium is set to github:AvengeMedia/DankMaterialShell/.../packages/nix";
}
