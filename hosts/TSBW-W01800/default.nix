# TSBW-W01800 — Jaide's work laptop (AMD APU, LUKS, Thunderbolt, YubiKey).
#
# flake-parts module that assembles the nixosSystem configuration.
# Shared modules come from config.nixosModules (collected in modules/options.nix).
# Host-specific modules are imported directly here.
{ inputs, config, lib, ... }:

{
  config.flake.nixosConfigurations.TSBW-W01800 = inputs.nixpkgs.lib.nixosSystem {
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
      config.nixosModules.fonts
      config.nixosModules.firmware
      config.nixosModules.keyring
      config.nixosModules.wm-mango
      config.nixosModules.wm-dms
      config.nixosModules.ai-hermes
      config.nixosModules.ai-mnemosyne
      config.nixosModules.cloud
      config.nixosModules.metadata
      config.nixosModules.secrets

      # ── Opt-in shared package modules ─────────────────────────────
      config.nixosModules.packages-network-tools
      config.nixosModules.packages-media
      config.nixosModules.packages-onepassword

      # ── Host-specific modules (imported directly) ────────────────
      ./hardware-configuration.nix
      (import ./state.nix)
      (import ./boot/boot.nix)
      (import ./hardware/graphics.nix)
      (import ./hardware/luks.nix)
      (import ./hardware/thunderbolt.nix)
      (import ./security/yubikey.nix)
      (import ./network/network.nix)
      (import ./network/dns.nix)
      (import ./desktop/plasma.nix)
      (import ./desktop/niri.nix)
      (import ./desktop/mango.nix)
      (import ./desktop/dms.nix)
      (import ./services/scanning.nix)
      (import ./services/steam.nix)
      (import ./services/upower.nix)
      (import ./services/gvfs.nix)
      (import ./services/power.nix)
      (import ./services/battery-services.nix)
      (import ./packages/system-packages.nix)
      (import ./packages/games.nix)
      (import ./packages/webbrowsers.nix)
      (import ./packages/disk-recovery.nix)
      (import ./packages/archives.nix)
      (import ./packages/windows-tools/windows-tools.nix)
      (import ./packages/work/communication.nix)
      (import ./shell/shell.nix)
      (import ./users/users.nix)

      # ── Overlays ──────────────────────────────────────────────────
      { nixpkgs.overlays = [ inputs.self.overlays.additions ]; }
      { nixpkgs.overlays = [ (import ../../overlays/millennium.nix { millennium-input = inputs.millennium; }) ]; }
    ];
  };
}