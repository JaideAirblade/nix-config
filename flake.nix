{
  description = "Jaide's NixOS flake configuration (dendritic pattern)";

  inputs = {
    # Main package source: the unstable channel.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";


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

  outputs = inputs@{ self, flake-parts, ... }:
    let
      # Import every top-level feature module. Lower-level package/overlay
      # expressions and generated hardware modules are deliberate exceptions.
      collectModules = dir:
        let
          entries = builtins.readDir dir;
        in
        builtins.concatLists (builtins.map
          (name:
            let
              path = dir + "/${name}";
              type = entries.${name};
              isNix = builtins.match ".*\\.nix" name != null;
              excluded =
                name == "default.nix"
                || name == "hardware-configuration.nix"
                || builtins.match ".*\\.overlay\\.nix" name != null;
            in
            if type == "directory" then collectModules path
            else if type == "regular" && isNix && !excluded then [ path ]
            else [ ])
          (builtins.attrNames entries));

      featureModules = collectModules ./modules ++ collectModules ./hosts;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = featureModules ++ [
        # Host entry points select a few merged roles and generated hardware.
        ./hosts/UwU/default.nix
        ./hosts/UwU-Server/default.nix
        ./hosts/TSBW-W01800/default.nix
      ];

      systems = [ "x86_64-linux" ];

      perSystem = { pkgs, system, ... }:
        let
          packagePkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        {
          formatter = pkgs.nixpkgs-fmt;

          checks = {
            formatting = pkgs.runCommand "nix-formatting-check"
              {
                nativeBuildInputs = [ pkgs.nixpkgs-fmt ];
              } ''
              nixpkgs-fmt --check ${self}
              touch $out
            '';

            dead-code = pkgs.runCommand "deadnix-check"
              {
                nativeBuildInputs = [ pkgs.deadnix ];
              } ''
              deadnix --fail ${self}
              touch $out
            '';

            static-analysis = pkgs.runCommand "statix-check"
              {
                nativeBuildInputs = [ pkgs.statix ];
              } ''
              statix check --config ${self} ${self}
              touch $out
            '';

            shell = pkgs.runCommand "shellcheck"
              {
                nativeBuildInputs = [ pkgs.findutils pkgs.shellcheck ];
              } ''
              find ${self} -type f -name '*.sh' -print0 \
                | xargs -0 --no-run-if-empty shellcheck --severity=warning
              touch $out
            '';

            regressions = pkgs.runCommand "repository-regressions"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.inetutils
                  pkgs.just
                  pkgs.openssh
                  pkgs.python3
                ];
              } ''
                cd ${self}
                bash tests/bootstrap-host-regressions.sh
                bash tests/bootstrap-authenticity-regressions.sh
                bash tests/bootstrap-network-regressions.sh
                bash tests/verify-installed-boot-regressions.sh
                bash tests/justfile-argument-regressions.sh
              python3 tests/ad-lab-name-regressions.py
              python3 tests/register-sops-host-regressions.py
              python3 tests/user-password-regressions.py
              python3 tests/private-accounts-regressions.py
              bash tests/set-private-password-hash-regressions.sh
              python3 tests/net-report-wifi-scan-regressions.py
              python3 tests/mnemosyne-activation-regressions.py
              touch $out
            '';
          };

          # The overlay and standalone outputs use the same nixpkgs revision.
          packages = (import ./pkgs packagePkgs) // {
            nixos-anywhere = inputs.nixos-anywhere.packages.${system}.default;
          };
        };

      flake = {
        # Custom packages overlay — exposes pkgs.betterbird, pkgs.octarine, etc.
        overlays = import ./overlays;
      };
    };
}
