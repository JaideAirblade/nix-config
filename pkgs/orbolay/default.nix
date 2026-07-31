{ lib
, stdenvNoCC
, fetchurl
, autoPatchelfHook
, makeWrapper
, alsa-lib
, fontconfig
, libglvnd
, libx11
, libxcursor
, libxi
, libxrandr
, libxtst
, libevdev
, libxkbcommon
, gcc
, vulkan-loader
, wayland
}:

stdenvNoCC.mkDerivation rec {
  pname = "orbolay";
  version = "3.6.0";

  src = fetchurl {
    url = "https://github.com/SpikeHD/Orbolay/releases/download/v${version}/orbolay-x86_64-unknown-linux-gnu";
    hash = "sha256-ZwAn9mie1qGzlH1afRmjRDT5PxNjbwGpAzVGq/1K19I=";
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    fontconfig
    libglvnd
    libx11
    libxcursor
    libxi
    libxrandr
    libxtst
    libevdev
    libxkbcommon
    gcc.cc.lib
    vulkan-loader
    wayland
  ];

  installPhase = ''
    install -Dm755 "$src" "$out/libexec/orbolay"

    install -Dm644 /dev/stdin "$out/share/applications/orbolay.desktop" <<'EOF'
    [Desktop Entry]
    Type=Application
    Name=Orbolay
    Comment=Native Discord voice overlay
    Exec=orbolay
    Icon=network-workgroup
    Categories=Network;InstantMessaging;Utility;
    Terminal=false
    StartupWMClass=orbolay
    Keywords=discord;voice;overlay;game;
    EOF
  '';

  postFixup = ''
    # winit loads X11 support dynamically. Force XWayland and expose the
    # runtime libraries that autoPatchelf cannot discover through dlopen.
    makeWrapper "$out/libexec/orbolay" "$out/bin/orbolay" \
      --unset WAYLAND_DISPLAY \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath buildInputs}"
  '';

  meta = with lib; {
    description = "Native Discord voice overlay";
    homepage = "https://github.com/SpikeHD/Orbolay";
    license = licenses.mit;
    mainProgram = "orbolay";
    platforms = [ "x86_64-linux" ];
  };
}
