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
  };

  outputs = inputs@{ self, nixpkgs, stable-nixpkgs, mangowm, dms, ... }: {
    nixosConfigurations = {
      # The hostname (set in modules/network/default.nix) must match this
      # key, or you must pass `--flake .#UwU` to nixos-rebuild.
      UwU = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        # Make `inputs` available to every module under modules = [...],
        # so e.g. modules/wm/mango/default.nix can do
        # `imports = [ inputs.mangowm.nixosModules.mango ];`.
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/UwU
        ];
      };
    };
  };
}