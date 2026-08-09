{
  description = "Jaide's NixOS flake configuration (dendritic pattern)";

  inputs = {
    # Main package source: the unstable channel.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Stable channel — used by the LaptopAP standalone installer ISO to
    # avoid unstable kernel/initrd regressions. Auto-updated monthly.
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";


    # Mango — Wayland compositor (dwl-based). Provides nixosModules.mango
    # (programs.mango.enable) and hmModules.mango.
    mangowm = {
      url = "github:mangowm/mango";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # niri flake removed: as of 2026-08-09, the niri-flake's libdisplay-info_0_2
    # compatibility shim is broken with newer nixpkgs (upstream still has a
    # `assert libdisplay-info_0_2.version == "0.2.0"` line that fails when
    # nixpkgs bumped the library). Mango is the only compositor on TSBW-W01800
    # now; niri is uninstalled. Re-add when niri-flake drops the legacy version
    # pin (see https://github.com/sodiboo/niri-flake/flake.nix).

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

    # Noctalia — Wayland-native desktop shell (bars, launcher, dock, lock,
    # notifications, control center, wallpapers, OSDs). See modules/wm/
    # noctalia/noctalia.nix for the role module and hosts/UwU/desktop/
    # noctalia-host.nix for the host-scoped wiring. The upstream flake
    # currently tracks v5-beta; pin via this input if a stable v4 is
    # needed instead. Verified on 2026-08-10:
    #   repo github:noctalia-dev/noctalia
    #   flake.nix exposes nixosModules.default + homeModules.default
    #   + hjemModules.default + packages.<system>.default
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Noctalia Greeter — companion login greeter for greetd, matching
    # the Noctalia look-and-feel. Loaded by modules/wm/noctalia/noctalia.nix.
    noctalia-greeter = {
      url = "github:noctalia-dev/noctalia-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Niri — scrollable-tiling Wayland compositor, used by UwU.
    # We do NOT use github:sodiboo/niri-flake because its pinned
    # `make-niri` function still asserts `libdisplay-info_0_2.version
    # == "0.2.0"`, which fails on current nixpkgs (libdisplay-info_0_2
    # was removed in favour of _0_3 / 0.4.0). All 10 most recent
    # niri-flake commits as of 2026-08-10 are just "Update flake.lock"
    # with no actual fix for this assertion.
    # Instead we use nixpkgs's built-in Niri module at
    # nixos/modules/programs/wayland/niri.nix, which uses pkgs.niri
    # (currently 26.04, built against the current libdisplay-info).
    # The option shape (`programs.niri.enable`, `programs.niri.package`)
    # is compatible with the niri-flake module, so swapping back to the
    # flake in the future (when the assertion is fixed) is a one-line
    # change in hosts/UwU/desktop/noctalia-host.nix.

    # Hermes Agent — Nous Research's terminal AI agent.
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hermes WebUI — community web UI for Hermes Agent (browser-based,
    # mobile-friendly, Tailscale-reachable). Wires through the upstream
    # NixOS module from `nix/nixosModules.nix` of the same repo; pinned to
    # a known-good commit so upstream refactors don't break the build.
    hermes-webui = {
      url = "github:nesquena/hermes-webui/c35b0659fec1d0656c5fa069826ac545f13b5654";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Honcho v3 — local AI-native memory backend for Hermes on UwU-Server.
    # Kept as source because upstream's supported self-host path builds its
    # locked Docker image from the repository checkout.
    honcho = {
      url = "github:plastic-labs/honcho/v3.0.12";
      flake = false;
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
      # expressions and generated hardware modules are deliberate exceptions
      # declared under `dendriticExceptions` below. Each entry maps the
      # *relative path* of an excusable file to a short justification that
      # survives in source so future contributors know why it isn't imported.
      #
      # The walker is parameterised on a string `prefix` that names the
      # subdirectory under the repo root. We pass the prefix explicitly
      # rather than computing it from `toString`, because Nix evaluates
      # the walker against the flake's `/nix/store/...-source` path —
      # `toString` would expose the store path, not the repo-relative
      # name the manifest uses.
      #
      # Each manifest entry has *some* consumer — a host entry point
      # imports the file directly, or a feature module merges it into
      # a shared role. The structural test
      # (`tests/dendritic-import-coverage-regressions.py`) asserts the
      # entry maps to a real file; the wiring test for that file
      # (e.g. `tests/boot-order-cleanup-regressions.py`) verifies the
      # actual import path.
      dendriticExceptions = {
        # Generated per-host hardware scan output. Safe to overwrite via
        # nixos-generate-config; not declarative. Each host entry point
        # imports the matching file directly into its `modules` list.
        "hosts/UwU/hardware-configuration.nix" = "generated by nixos-generate-config; direct host import";
        "hosts/UwU-Server/hardware-configuration.nix" = "generated by nixos-generate-config; direct host import";
        "hosts/TSBW-W01800/hardware-configuration.nix" = "generated by nixos-generate-config; direct host import";
        "hosts/Projet-Printserver/hardware-configuration.nix" = "generated by nixos-generate-config; direct host import";
        "hosts/OwO-Family/hardware-configuration.nix" = "generated by nixos-generate-config; direct host import";

        # Lower-level NixOS modules that need `pkgs` and `lib` from the
        # NixOS module system, not the smaller `{ lib, config, inputs, ... }`
        # the dendritic walker hands to top-level feature files. The host
        # entry point imports the module directly into its `modules = [ ... ]`
        # list — the wiring test (`tests/boot-order-cleanup-regressions.py`)
        # asserts the direct import is paired with this manifest entry.
        "hosts/UwU-Server/boot-order.nix" = "dendritic lower-level NixOS module; imported directly by hosts/UwU-Server/default.nix";
      };

      isException = name: builtins.hasAttr name dendriticExceptions;
      collectModules = root: prefix:
        let
          entries = builtins.readDir root;
        in
        builtins.concatLists (builtins.map
          (entry:
            let
              path = root + "/${entry}";
              type = entries.${entry};
              repoRelPath = prefix + "/" + entry;
              isNix = builtins.match ".*\\.nix" entry != null;
              excluded =
                entry == "default.nix"
                || builtins.match ".*\\.overlay\\.nix" entry != null
                || isException repoRelPath;
              childPrefix = if prefix == "" then entry else prefix + "/" + entry;
            in
            if type == "directory" then collectModules path childPrefix
            else if type == "regular" && isNix && !excluded then
              [ path ]
            else [ ])
          (builtins.attrNames entries));
      featureModules =
        collectModules ./modules "modules"
        ++ collectModules ./hosts "hosts";
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = featureModules ++ [
        # Host entry points select a few merged roles and generated hardware.
        ./hosts/UwU/default.nix
        ./hosts/UwU-Server/default.nix
        ./hosts/TSBW-W01800/default.nix
        ./hosts/Projet-Printserver/default.nix
        ./hosts/LaptopAP/default.nix
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

            server-greeter =
              assert !self.nixosConfigurations.UwU-Server.config.programs.steam.gamescopeSession.enable;
              pkgs.runCommand "uwu-server-greeter-check" { } ''
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
              python3 tests/tailscale-mesh-regressions.py
              python3 tests/netbird-mesh-regressions.py
              python3 tests/user-unit-scope-regressions.py
              bash tests/set-private-password-hash-regressions.sh
              python3 tests/net-report-wifi-scan-regressions.py
              python3 tests/mnemosyne-activation-regressions.py
              python3 tests/local-honcho-regressions.py
              python3 tests/server-hermes-extensions-regressions.py
              python3 tests/server-hermes-mobile-bridge-regressions.py
              python3 tests/server-omniroute-regressions.py
              SOPS_ROOT=${inputs.nixos-secrets} python3 tests/server-hermes-webui-regressions.py
              python3 tests/data-pool-layout-regressions.py
              python3 tests/boot-order-cleanup-regressions.py
              python3 tests/dendritic-import-coverage-regressions.py
              touch $out
            '';
          };

          # The overlay and standalone outputs use the same nixpkgs revision.
          packages = (import ./pkgs packagePkgs) // {
            nixos-anywhere = inputs.nixos-anywhere.packages.${system}.default;
            # Bootable ISO for the LaptopAP unattended installer.
            laptopAP-iso = self.nixosConfigurations.LaptopAP.config.system.build.isoImage;
          };
        };

      flake = {
        # Custom packages overlay — exposes pkgs.betterbird, pkgs.octarine, etc.
        overlays = import ./overlays;

        # NixOS module that installs the witr process-tracing CLI on any host
        # that imports it. Each host's default.nix adds `inputs.self.nixosModules.witr`
        # to its modules list. witr ships in nixpkgs (both unstable and stable
        # channels as of 2026-08-07), so no flake-input overlay is required —
        # `pkgs.witr` resolves directly.
        nixosModules.witr =
          { pkgs, ... }:
          {
            environment.systemPackages = [ pkgs.witr ];
          };
      };
    };
}
