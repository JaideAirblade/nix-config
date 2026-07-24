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

      # Disko — declarative disk layout
      inputs.disko.nixosModules.disko
      config.nixosModules.disko
      (import ./disk-layout.nix)

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
    ];
  };
}