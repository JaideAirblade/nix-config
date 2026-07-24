# OwO-Family — family PC at Jaide's parents' house.
# Old Intel CPU, NVIDIA GTX 750 Ti.
# Same base setup as UwU (shared modules) but with older GPU drivers
# and no gaming/OSINT/animejanai stack.
{ inputs, config, lib, ... }:

{
  config.flake.nixosConfigurations.OwO-Family = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";

    specialArgs = {
      inherit inputs;
      pkgs-stable = config.pkgs-stable;
    };

    modules = [
      # ── Shared modules (same as UwU) ──────────────────────────────
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

      # ── Opt-in shared packages ────────────────────────────────────
      config.nixosModules.packages-file-manager
      config.nixosModules.packages-onepassword
      config.nixosModules.packages-network-tools
      config.nixosModules.packages-media
      config.nixosModules.virtualisation
      config.nixosModules.virtualisation-ad-lab

      # ── Disko — btrfs with subvolumes + deduplication ──────────────
      inputs.disko.nixosModules.disko
      config.nixosModules.disko
      config.nixosModules.disko-btrfs-dedup
      (import ./disk-layout.nix)

      # ── Host-specific modules ────────────────────────────────────
      ./hardware-configuration.nix
      (import ./state.nix)
      (import ./graphics/graphics.nix)
      (import ./gaming/gaming.nix)
      (import ./network/network.nix)
      (import ./shell/shell.nix)
      (import ./users/users.nix)
      (import ./packages/packages.nix)

      # ── Overlays ──────────────────────────────────────────────────
      { nixpkgs.overlays = [ inputs.self.overlays.additions ]; }
      { nixpkgs.overlays = [ (import ../../overlays/millennium.nix { millennium-input = inputs.millennium; }) ]; }
    ];
  };
}