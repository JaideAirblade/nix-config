# Macrotool (GTK 4 edition) — native GTK 4 game macro/automation tool.
# https://github.com/JaideAirblade/macrotool-gtk4
#
# Builds from source using buildRustPackage (handles cargo in the nix sandbox
# by fetching + vendoring crates from the Cargo.lock).
#
# To rebuild after changes:
#   cd ~/Projects/Macrotool-gtk4 && git add -A && git commit && git push
#   # Update rev + cargoHash below, then:
#   cd ~/nixos && sudo nixos-rebuild switch --flake .#UwU
{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, wrapGAppsHook4
, gtk4
, gtk4-layer-shell
, glib
, libX11
,
}:

rustPlatform.buildRustPackage (_finalAttrs: {
  pname = "macrotool-gtk4";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "JaideAirblade";
    repo = "macrotool-gtk4";
    rev = "559eed7056b8db3d594b3c971ced02c0f70f0c37";
    hash = "sha256-2FFNqFqwCZl4ocVzHusCdvA+rJXafsnswEwd3XuV1cU=";
  };

  cargoHash = "sha256-cDSE+EidwMhuQl+B6brHeo3/LsKuVd+TOi+cZyOnnRk=";

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook4
  ];

  buildInputs = [
    gtk4
    gtk4-layer-shell
    glib
    libX11
  ];

  # The source doesn't include target/ (gitignored), so no pre-built binary.
  # buildRustPackage will compile from source.

  postInstall = ''
    # Desktop entry
    mkdir -p $out/share/applications
    cat > $out/share/applications/macrotool.desktop << EOF
    [Desktop Entry]
    Type=Application
    Name=Macrotool
    Comment=Game macro/automation tool for Linux/Wayland
    Exec=macrotool
    Icon=input-gaming
    Categories=Game;Utility;
    Terminal=false
    StartupWMClass=macrotool
    Keywords=macro;automation;game;hotkey;
    EOF
  '';

  meta = {
    description = "Game macro/automation tool for Linux/Wayland (native GTK 4)";
    homepage = "https://github.com/JaideAirblade/macrotool-gtk4";
    mainProgram = "macrotool";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
})
