# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#betterbird' or 'nix build .#octarine'
pkgs: {
  betterbird = pkgs.callPackage ./betterbird { };
  octarine = pkgs.callPackage ./octarine { };
  hytale = pkgs.callPackage ./hytale { };
}