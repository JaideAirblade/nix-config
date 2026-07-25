# UwU — Jaide's desktop PC (AMD CPU, NVIDIA RTX 3080).
#
# flake-parts module that assembles the nixosSystem configuration.
# Shared modules come from config.nixosModules (collected in modules/options.nix).
# Host-specific modules are imported directly here and also assigned to
# config.nixosModules so they merge with the deferredModule type.
{ inputs, config, lib, ... }:

{
  config.flake.nixosConfigurations.UwU = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";

    specialArgs = {
      inherit inputs;
      pkgs-stable = config.pkgs-stable;
    };

    modules = [
      # ── Shared modules (every host wants these) ───────────────────
      config.nixosModules.boot
      config.nixosModules.nix
      config.nixosModules.network
      config.nixosModules.firewall
      config.nixosModules.security
      config.nixosModules.locale
      config.nixosModules.users
      config.nixosModules.audio
      config.nixosModules.printing
      config.nixosModules.packages-base
      config.nixosModules.shell
      config.nixosModules.bluetooth
      config.nixosModules.theming
      config.nixosModules.theming-millennium
      config.nixosModules.fonts
      config.nixosModules.firmware
      config.nixosModules.keyring
      config.nixosModules.wm-mango
      config.nixosModules.wm-dms
      config.nixosModules.ai-hermes
      config.nixosModules.ai-mnemosyne
      config.nixosModules.cloud
      config.nixosModules.facemask
      config.nixosModules.metadata
      config.nixosModules.secrets

      # ── VPN / remote access (AmneziaWG mesh + stealth SSH) ───────────
      config.nixosModules.amneziawg-mesh
      config.nixosModules.stealth-ssh
      {
        # AmneziaWG full mesh — every host is server + client
        services.amneziawg-mesh = {
          enable = true;
          thisHost = "UwU";
          port = 443;
          enableUPnP = true;
          # TODO: Switch to per-host key after updating sops:
          #   privateKeySecret = "awg_private_key_UwU";
          privateKeySecret = "awg_private_key";  # using existing key during migration
          hosts = {
            UwU          = {
              vpnIP = "10.100.0.1";
              publicKey = "NIYTYZUDk5cIApTIRTn+6W5A/iNzlpYtKF023pmBWms=";
              # Endpoint auto-discovered via UPnP; set DDNS later if needed
              endpoint = "";
            };
            TSBW-W01800  = {
              vpnIP = "10.100.0.2";
              publicKey = "Am3ruSNP1euGL3EHXcBzR5ShKxBiP0TMOirRKwdQwwM=";
              # Work laptop — roaming, no stable endpoint
              endpoint = "";
            };
            OwO-Family   = {
              vpnIP = "10.100.0.3";
              publicKey = "WsL8kw4MZPiD6gw49RDU9ZDTmhEUvRGIJbKqWGJ1qjU=";
              # Family PC — endpoint set after port forwarding is configured
              endpoint = "";
            };
          };
        };

        # Stealth SSH — FIDO2-only, VPN-only
        services.stealth-ssh = {
          enable = true;
          listenAddress = "10.100.0.1";
          port = 22;
          user = "jaide";
          authorizedKeys = [ ];
        };
      }

      # ── Virtualisation (libvirt + AD test lab) ──────────────────────
      config.nixosModules.virtualisation
      config.nixosModules.virtualisation-ad-lab

      # ── Disko — declarative disk layout ─────────────────────────────
      # DISABLED: disk was partitioned manually (labels: EFI, root), not by
      # disko (which expects labels: disk-main-ESP, disk-main-root).
      # Enable these when reinstalling via nixos-anywhere so disko can
      # repartition + relabel the disk to match.
      # inputs.disko.nixosModules.disko
      # config.nixosModules.disko
      # (import ./disk-layout.nix)

      # ── Opt-in shared package modules (UwU wants these) ────────────
      config.nixosModules.packages-file-manager
      config.nixosModules.packages-onepassword
      config.nixosModules.packages-network-tools
      config.nixosModules.packages-osint
      config.nixosModules.packages-media
      config.nixosModules.packages-animejanai

      # ── Host-specific modules (imported directly) ────────────────
      ./hardware-configuration.nix
      (import ./state.nix)
      (import ./graphics/graphics.nix)
      (import ./gaming/gaming.nix)
      (import ./macrotool/macrotool.nix)
      (import ./devices/devices.nix)
      (import ./packages/packages.nix)
      (import ./packages/flatpak.nix)
      (import ./network/network.nix)
      (import ./shell/shell.nix)
      (import ./users/users.nix)

      # ── Overlays ──────────────────────────────────────────────────
      { nixpkgs.overlays = [ inputs.self.overlays.additions ]; }
      { nixpkgs.overlays = [ (import ../../overlays/millennium.nix { millennium-input = inputs.millennium; }) ]; }
      # Patch amneziawg kernel module for Linux 7.x (ipv6_stub removed)
      { nixpkgs.overlays = [ (import ../../overlays/amneziawg-kernel7-fix.nix) ]; }
      { nixpkgs.overlays = [ (import ../../overlays/python314-fixes.nix) ]; }
    ];
  };
}