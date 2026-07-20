{
  description = "Jaide's NixOS flake configuration";

  inputs = {
    # Main package source: the unstable channel.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Stable channel, available to modules as `inputs.stable-nixpkgs`
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
    # Used as NixOS modules (nixosModules.dank-material-shell + nixosModules.greeter)
    # so we don't need home-manager. `follows` keeps nixpkgs in sync.
    # Using master (-git) per the user's request to consume the shell directly
    # from the official repo; option names follow the flake module's
    # `programs.dank-material-shell.*` naming.
    dms = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # DankCalendar — calendar backend for DMS 1.5+ (replaces khal).
    # Used by the TSBW-W01800 work host. UwU doesn't import it.
    dankcalendar = {
      url = "github:AvengeMedia/dankcalendar";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hermes Agent — Nous Research's terminal AI agent.
    # Consumed via its overlay (modules/ai/hermes-agent.nix) so `pkgs.hermes-agent`
    # is the official build. `follows` keeps nixpkgs in sync to avoid a second
    # copy of nixpkgs in the closure.
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Temporary pin of nixpkgs to the open IVPN update PR (kilyanni's
    # #542306: ivpn/ivpn-service/ivpn-ui 3.15.6 -> 3.15.13). Consumed only
    # via an overlay in modules/network/ivpn-overlay.nix so just the three
    # packages come from here; everything else stays on the main input.
    # Drop this input + the overlay once the PR lands in nixos-unstable.
    nixpkgs-ivpn.url = "github:NixOS/nixpkgs/pull/542306/head";
  };

  outputs = inputs@{ self, nixpkgs, stable-nixpkgs, mangowm, niri, dms, dankcalendar, hermes-agent, nixpkgs-ivpn, ... }: let
    # Pre-create the stable-nixpkgs instance here so submodules can use
    # `pkgs-stable` without each calling `import stable-nixpkgs { ... }`
    # (which would spawn a new nixpkgs evaluation every time — the
    # "1000 instances of nixpkgs" problem from the guide's
    # downgrade-or-upgrade-packages chapter).
    system = "x86_64-linux";
    pkgs-stable = import stable-nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    # Custom packages overlay — exposes pkgs.betterbird, pkgs.octarine.
    # Applied by each host via nixpkgs.overlays in their host config.
    overlays = import ./overlays;

    nixosConfigurations = {
      # The hostname (set in modules/network/default.nix) must match this
      # key, or you must pass `--flake .#UwU` to nixos-rebuild.
      UwU = nixpkgs.lib.nixosSystem {
        inherit system;
        # Make `inputs` and `pkgs-stable` available to every module under
        # modules = [...].  `inputs` lets e.g. modules/wm/mango/default.nix
        # do `imports = [ inputs.mangowm.nixosModules.mango ];`.  `pkgs-stable`
        # lets any module pull a package from the stable nixpkgs branch
        # without creating a new nixpkgs instance.
        specialArgs = { inherit inputs pkgs-stable; };
        modules = [
          # Apply the custom-packages overlay so pkgs.betterbird / pkgs.octarine
          # are available to this host's modules.
          { nixpkgs.overlays = [ inputs.self.overlays.additions ]; }
          ./hosts/UwU
        ];
      };

      # TSBW-W01800 — Jaide's work laptop (AMD, LUKS, Thunderbolt, YubiKey).
      # Hostname set in hosts/TSBW-W01800/network/network.nix.
      TSBW-W01800 = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs pkgs-stable; };
        modules = [
          { nixpkgs.overlays = [ inputs.self.overlays.additions ]; }
          ./hosts/TSBW-W01800
        ];
      };
    };
  };
}