# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#betterbird' or 'nix build .#octarine'
pkgs: {
  betterbird = pkgs.callPackage ./betterbird { };
  octarine = pkgs.callPackage ./octarine { };
  hytale = pkgs.callPackage ./hytale { };
  helium-bin = pkgs.callPackage ./helium-bin { };
  legcord = pkgs.callPackage ./legcord { };
  orbolay = pkgs.callPackage ./orbolay { };
  net-report = pkgs.callPackage ./net-report { };
  nym-vpnd = pkgs.callPackage ./nym-vpnd { };
  macrotool-gtk4 = pkgs.callPackage ./macrotool-gtk4 { };
  omniroute = pkgs.callPackage ./omniroute { };

  officecli = pkgs.callPackage ./officecli { };
  herm-tui = pkgs.callPackage ./herm-tui { };
}
