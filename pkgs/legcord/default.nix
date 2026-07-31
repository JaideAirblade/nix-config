# Legcord — upstream AppImage packaged declaratively until nixpkgs catches up.
# https://github.com/Legcord/Legcord/releases
{ lib
, appimageTools
, fetchurl
,
}:

appimageTools.wrapType2 rec {
  pname = "legcord";
  version = "1.3.0";

  src = fetchurl {
    url = "https://github.com/Legcord/Legcord/releases/download/v${version}/Legcord-${version}-linux-x86_64.AppImage";
    hash = "sha256-Imk3pIH1B/mqkqYGa2iphuTP3FsE37tvTOsnc6Gb1Ik=";
  };

  meta = {
    description = "Lightweight, alternative desktop client for Discord";
    homepage = "https://github.com/Legcord/Legcord";
    changelog = "https://github.com/Legcord/Legcord/releases/tag/v${version}";
    license = lib.licenses.gpl3Only;
    mainProgram = "legcord";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
