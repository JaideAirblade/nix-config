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
      config.nixos.modules.office
      config.nixos.modules.maintenance
      config.nixos.modules.observability
      config.nixos.hosts."TSBW-W01800"

      # Generated lower-level module exception.
      ./hardware-configuration.nix

      # Prometheus node_exporter — direct import (the walker excludes it
      # from flake-parts imports because networking.firewall.* trips
      # flake-parts evaluation; see flake.nix's dendriticExceptions).
      ./../modules/observability/node-exporter.nix

      # Heartbeat dead-man's-switch — same pattern. TSBW doesn't use
      # btrfs (LUKS + ext4), so no btrfs-scrub here — UwU and
      # UwU-Server get it instead.
      ./../modules/maintenance/heartbeat.nix

      # witr — process/port/container/file tracing CLI. See flake.nix.
      inputs.self.nixosModules.witr

      { nixpkgs.overlays = [ inputs.self.overlays.additions ]; }
      { nixpkgs.overlays = [ inputs.self.overlays.python-package-fixes ]; }
      # Enable CONFIG_WIFI_DISPLAY=y in wpa_supplicant for Miracast/WFD
      # support. Required by gnome-network-displays to discover P2P peers
      # via NetworkManager. See overlays/wpa-supplicant-wifi-display.nix.
      { nixpkgs.overlays = [ inputs.self.overlays.wpa-supplicant-wifi-display ]; }
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
          # TSBW runs DMS (per hosts/TSBW-W01800/desktop/dms.nix),
          # so the DMS NetbirdStatus plugin needs the `netbird` shim.
          dms.enable = true;
        };
      }
    ];
  };
}
