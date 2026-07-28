# OwO-Family desktop configuration entry point.
# Disko is intentionally not selected until the machine has a verified
# /dev/disk/by-id target; this exported configuration is safe to evaluate and
# rebuild without carrying a placeholder destructive disk layout.
{ config, inputs, ... }:
{
  flake.nixosConfigurations.OwO-Family = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";

    modules = [
      config.nixos.modules.common
      config.nixos.modules.fileManager
      config.nixos.modules.virtualisation
      config.nixos.modules.adLab
      config.nixos.hosts."OwO-Family"

      # Generated lower-level module exception.
      ./hardware-configuration.nix

      { nixpkgs.overlays = [ inputs.self.overlays.additions ]; }
      { nixpkgs.overlays = [ (import ../../overlays/millennium.nix { millennium-input = inputs.millennium; }) ]; }
    ];
  };
}
