# TSBW-W01800 workstation configuration entry point.
{ config, inputs, ... }:
{
  flake.nixosConfigurations.TSBW-W01800 = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";

    modules = [
      config.nixos.modules.common
      config.nixos.modules.automationAccounts
      config.nixos.modules.netbirdMesh
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
        # Netbird mesh — sole mesh on this host as of 2026-08-09.
        # See docs/netbird-mesh.md for the migration rationale. The
        # pre-Netbird mesh (Tailscale) had its remoteMesh opt-in
        # removed in the same commit.
        services.netbirdMesh = {
          enable = true;
          nodeRole = "work";
          exposeSshOnLan = false;
        };
      }
    ];
  };
}
