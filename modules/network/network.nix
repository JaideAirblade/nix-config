# Networking.
#
# Hostname is intentionally NOT set here — each host sets its own in
# hosts/<name>/network/network.nix so the shared module stays portable.
{ inputs, ... }:

{
  networking.networkmanager.enable = true;

  services.ivpn.enable = true;

  # Pull ivpn/ivpn-service/ivpn-ui from the pinned nixpkgs-ivpn input
  # (PR #542306: 3.15.6 -> 3.15.13) ahead of the merge. Drop once landed.
  nixpkgs.overlays = [ (import ./ivpn-overlay.nix { inherit inputs; }) ];
}