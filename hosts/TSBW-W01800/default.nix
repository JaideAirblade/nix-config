# TSBW-W01800 workstation configuration entry point.
{ config, inputs, ... }:
{
  flake.nixosConfigurations.TSBW-W01800 = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";

    modules = [
      config.nixos.modules.common
      config.nixos.modules.automationAccounts
      config.nixos.modules.remoteMesh
      config.nixos.modules.virtualisation
      config.nixos.hosts."TSBW-W01800"

      # Generated lower-level module exception.
      ./hardware-configuration.nix

      # witr — process/port/container/file tracing CLI. See flake.nix.
      inputs.self.nixosModules.witr

      { nixpkgs.overlays = [ inputs.self.overlays.additions ]; }
      { nixpkgs.overlays = [ inputs.self.overlays.python-package-fixes ]; }
      { nixpkgs.overlays = [ (import ../../overlays/millennium.nix { millennium-input = inputs.millennium; }) ]; }
      {
        services.privateMesh = {
          nodeRole = "work";
          exposeSshOnLan = false;
        };
      }
    ];
  };
}
