{
  description = "Jaide's NixOS flake configuration";

  inputs = {
    # Main package source: the unstable channel.
    # System-level packages and home-manager both follow this.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Stable channel, available to modules as `inputs.stable-nixpkgs`
    # for pinning individual packages to a stable release when needed.
    stable-nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # home-manager, used for managing user-level (home directory) configuration.
    # `master` tracks nixos-unstable; `release-26.05` would track stable.
    # `follows` keeps home-manager's nixpkgs in sync with the one above,
    # avoiding duplicate / divergent nixpkgs versions in the closure.
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, stable-nixpkgs, home-manager, ... }: {
    nixosConfigurations = {
      # The hostname (set in configuration.nix) must match this key,
      # or you must pass `--flake .#Uwu` to nixos-rebuild.
      Uwu = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        # Make `inputs` available to every module under modules = [...],
        # so configuration.nix / home.nix can reference e.g.
        # `inputs.stable-nixpkgs.legacyPackages.x86_64-linux.<pkg>`.
        specialArgs = { inherit inputs; };
        modules = [
          ./configuration.nix

          # Load home-manager as a NixOS module so it is applied
          # automatically whenever `nixos-rebuild switch` runs —
          # no separate `home-manager switch` needed.
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.jaide = import ./home.nix;
            # Pass `inputs` down to home.nix too, in case it needs them
            # (e.g. to pull a package from stable-nixpkgs).
            home-manager.extraSpecialArgs = { inherit inputs; };
          }
        ];
      };
    };
  };
}