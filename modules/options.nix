# Dendritic pattern: top-level options + module collector.
#
# This file declares the `nixosModules` deferredModule slot and the
# `pkgs-stable` option, then imports every NixOS module file (shared +
# host-specific) and assigns each one to config.nixosModules.<name>.
# The host entry points (hosts/<name>/default.nix) read from
# config.nixosModules to assemble their nixosSystem modules list.
#
# This is the ONLY file that needs to change when adding a new module —
# add one line `config.nixosModules.<name> = import ./path/to/file.nix;`.
{ lib, inputs, ... }:

{
  options = {
    # Storage for NixOS modules. Each key is a module name, each value
    # is a NixOS module (function or attribute set). The host entry points
    # pull individual modules by name: config.nixosModules.boot, etc.
    # We use `attrsOf (lib.types.unspecified)` so modules can be functions
    # (taking NixOS module args like { config, pkgs, ... }) or plain
    # attribute sets — the NixOS module system handles both when they're
    # passed in the `modules` list of nixosSystem.
    nixosModules = lib.mkOption {
      type = lib.types.attrsOf (lib.types.unspecified);
      default = { };
    };

    # Pre-created stable nixpkgs instance (avoids "1000 instances" anti-pattern).
    # Set here, read by host entry points via config.pkgs-stable.
    pkgs-stable = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };

  config = {
    pkgs-stable = import inputs.stable-nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };

    # ── Shared modules (from modules/**) ───────────────────────────
    # Every shared NixOS module is assigned here. The host entry points
    # pull the ones they want into their nixosSystem modules list.
    nixosModules = {
      # Core system
      boot = import ./boot/boot.nix;
      nix = import ./nix/nix.nix;
      network = import ./network/network.nix;
      firewall = import ./firewall/firewall.nix;
      security = import ./security/security.nix;
      locale = import ./locale/locale.nix;
      users = import ./users/users.nix;
      audio = import ./audio/audio.nix;
      printing = import ./printing/printing.nix;
      shell = import ./shell/shell.nix;
      bluetooth = import ./bluetooth/bluetooth.nix;
      fonts = import ./fonts/fonts.nix;
      firmware = import ./firmware/firmware.nix;
      keyring = import ./keyring/keyring.nix;
      facemask = import ./facemask/facemask.nix;
      metadata = import ./metadata/metadata.nix;

      # Theming
      theming = import ./theming/theming.nix;
      theming-millennium = import ./theming/millennium-theme.nix;

      # Window managers
      wm-mango = import ./wm/mango/mango.nix;
      wm-dms = import ./wm/dms/dms.nix;

      # AI
      ai-hermes = import ./ai/hermes-agent.nix;
      ai-mnemosyne = import ./ai/mnemosyne.nix;

      # Cloud
      cloud = import ./cloud/gdrive-sync.nix;

      # Secrets
      secrets = import ./secrets/secrets.nix;

      # Disko — declarative disk layout (imported per-host, not always-on)
      disko = import ./disko/disko.nix;
      disko-single-disk-xfs = import ./disko/single-disk-xfs.nix;
      disko-single-disk-btrfs = import ./disko/single-disk-btrfs.nix;
      disko-btrfs-dedup = import ./disko/btrfs-dedup.nix;

      # ── Opt-in shared package modules ─────────────────────────────
      # These are NOT included by default — each host pulls the ones
      # it wants into its modules list.
      packages-base = import ./packages/packages.nix;
      packages-file-manager = import ./packages/file-manager/file-manager.nix;
      packages-media = import ./packages/media/media.nix;
      packages-animejanai = import ./packages/media/animejanai.nix;
      packages-onepassword = import ./packages/onepassword/onepassword.nix;
      packages-network-tools = import ./packages/network-tools/network-tools.nix;
      packages-osint = import ./packages/osint/osint.nix;
    };
  };
}