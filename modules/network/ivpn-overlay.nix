# Overlay that pulls ivpn, ivpn-service, and ivpn-ui from the pinned
# nixpkgs-ivpn input (PR #542306: 3.15.6 -> 3.15.13) ahead of the merge.
#
# Imported by network.nix alongside services.ivpn.enable. The overlay only
# swaps the three IVPN packages; everything else comes from the main nixpkgs.
#
# Remove this file and the nixpkgs-ivpn flake input once the PR lands in
# nixos-unstable (flake.lock will pick it up via `just up`).
{ inputs }:
final: prev: {
  inherit (inputs.nixpkgs-ivpn.legacyPackages.${final.stdenv.hostPlatform.system})
    ivpn
    ivpn-service
    ivpn-ui
  ;
}