{
  description = "Jaide's NixOS flake configuration (dendritic pattern)";

  inputs = {
    # Main package source: the unstable channel.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Stable channel, available to modules as `config.pkgs-stable`
    # for pinning individual packages to a stable release when needed.
    stable-nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Mango — Wayland compositor (dwl-based). Provides nixosModules.mango
    # (programs.mango.enable) and hmModules.mango.
    mangowm = {
      url = "github:mangowm/mango";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Niri — scrollable tiling Wayland compositor.
    # Used by the TSBW-W01800 work host. Provides nixosModules.niri and
    # homeManagerModules.niri. UwU doesn't import it.
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # DankMaterialShell — desktop shell (bar/launcher/lock/notifs) + greeter.
    dms = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # DankCalendar — calendar backend for DMS 1.5+ (replaces khal).
    dankcalendar = {
      url = "github:AvengeMedia/dankcalendar";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # DankGreeter — now a separate flake (split from DMS as of July 2026).
    dank-greeter = {
      url = "github:AvengeMedia/dank-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hermes Agent — Nous Research's terminal AI agent.
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Millennium — Steam skin/theme loader.
    millennium = {
      url = "github:SteamClientHomebrew/Millennium?dir=packages/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # sops-nix — declarative secrets management via Mozilla SOPS + age.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Encrypted secrets — separate PRIVATE repo.
    nixos-secrets = {
      url = "git+ssh://git@github.com/JaideAirblade/nixos-secrets.git?ref=main";
      flake = false;
    };

    # Temporary pin of nixpkgs to the open IVPN update PR.
    nixpkgs-ivpn.url = "github:NixOS/nixpkgs/pull/542306/head";

    # flake-parts — module system for flakes (enables the dendritic pattern).
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # disko — declarative disk partitioning for nixos-anywhere.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nixos-anywhere — zero-touch NixOS provisioning via SSH.
    # Not a NixOS module — it's a CLI tool run from the workstation.
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, stable-nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        # The module collector — declares options.nixosModules (deferredModule)
        # and imports every shared NixOS module file into it.
        ./modules/options.nix
        # Host entry points — each assembles a nixosSystem from config.nixosModules
        # + host-specific modules imported directly.
        ./hosts/UwU/default.nix
        ./hosts/TSBW-W01800/default.nix
      ];

      systems = [ "x86_64-linux" ];

      perSystem = { pkgs, ... }: {
        # Standalone package outputs — `nix build .#betterbird`, etc.
        packages = {
          betterbird = (import stable-nixpkgs { system = "x86_64-linux"; config.allowUnfree = true; }).callPackage ./pkgs/betterbird { };
          octarine = (import stable-nixpkgs { system = "x86_64-linux"; config.allowUnfree = true; }).callPackage ./pkgs/octarine { };
          hytale = (import stable-nixpkgs { system = "x86_64-linux"; config.allowUnfree = true; }).callPackage ./pkgs/hytale { };
          net-report = (import stable-nixpkgs { system = "x86_64-linux"; config.allowUnfree = true; }).callPackage ./pkgs/net-report { };
        };
      };

      flake = {
        # Custom packages overlay — exposes pkgs.betterbird, pkgs.octarine, etc.
        overlays = import ./overlays;
      };
    };
}