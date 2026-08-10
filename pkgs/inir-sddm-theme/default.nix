# iNiR's ii-pixel SDDM theme — vendored as a Nix package so SDDM can
# find it at /share/sddm/themes/ii-pixel. Pinned to the same upstream
# commit that the nixos configuration captures. Re-build the flake to
# bump the theme; the new rev must match what inir-shell pulls in.
#
# Source: https://github.com/snowarch/iNiR/tree/main/dots/sddm/pixel
# Theme metadata: dots/sddm/pixel/metadata.desktop declares
#   Theme-API=2.0, QtVersion=6, MainScript=Main.qml
# which is the modern SDDM theme API.
#
# We do NOT use the Arch PKGBUILD path (`distro/arch/inir-meta`) because
# that's an AUR shape — NixOS packages the theme directly.
{ lib
, stdenvNoCC
, fetchFromGitHub
}:
stdenvNoCC.mkDerivation {
  pname = "inir-sddm-theme";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "snowarch";
    repo = "iNiR";
    rev = "f1e8a6ee5283a51640e715fc083881d88e02a5bf";
    hash = "sha256-159pMRQZZKzbYBzGwJUlEYhtIulGb6bNG1i04NbPHkg=";
  };

  sourceRoot = "source/dots/sddm/pixel";

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/sddm/themes/ii-pixel"
    cp -r . "$out/share/sddm/themes/ii-pixel/"
    runHook postInstall
  '';

  meta = with lib; {
    description = "ii-pixel SDDM login theme — iNiR Material You dynamic colors";
    homepage = "https://github.com/snowarch/iNiR";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
