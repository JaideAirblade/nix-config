{ lib
, rustPlatform
, fetchFromGitHub
, fetchurl
, pkg-config
, makeWrapper
, alsa-lib
, fontconfig
, freetype
, glib
, gtk3
, libglvnd
, libx11
, libxcursor
, libxi
, libxrandr
, libxtst
, libevdev
, libxkbcommon
, gcc
, openssl
, vulkan-loader
, wayland
}:

let
  skiaBinaries = fetchurl {
    url = "https://github.com/marc2332/rust-skia/releases/download/0.98.0/skia-binaries-a9bd25883c31d7ac2b2b-x86_64-unknown-linux-gnu-egl-gl-jpegd-jpege-svg-textlayout-vulkan-wayland-webpd-webpe-x11.tar.gz";
    hash = "sha256-0ZHblarMr0gUfMa0ScDS32+CwzKk7/o7NniH9tWYvYs=";
  };
in
rustPlatform.buildRustPackage rec {
  pname = "orbolay";
  version = "3.6.0-unstable-2026-08-15";

  rev = "1855287ec5fccebf680328567eeb53655fa96c75";

  src = fetchFromGitHub {
    owner = "SpikeHD";
    repo = "Orbolay";
    inherit rev;
    hash = "sha256-LbAmpRVkAhwZfVNIhkAIniyBiuz93RquiSSg2vkB2os=";
  };

  cargoHash = "sha256-SfkIvsbv7UF1M1jFuGVlK72xXs5bz5xi/nLF1NOFuOk=";

  env = {
    GIT_HASH = builtins.substring 0 7 rev;
    SKIA_BINARIES_URL = "file://${skiaBinaries}";
  };

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    fontconfig
    freetype
    glib
    gtk3
    libglvnd
    libx11
    libxcursor
    libxi
    libxrandr
    libxtst
    libevdev
    libxkbcommon
    gcc.cc.lib
    openssl
    vulkan-loader
    wayland
  ];

  postInstall = ''
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
    # runtime libraries that it discovers through dlopen.
    wrapProgram "$out/bin/orbolay" \
      --unset WAYLAND_DISPLAY \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath buildInputs}"
  '';

  meta = with lib; {
    description = "Native Discord voice overlay";
    homepage = "https://github.com/SpikeHD/Orbolay";
    changelog = "https://github.com/SpikeHD/Orbolay/compare/v3.6.0...${rev}";
    license = licenses.mit;
    mainProgram = "orbolay";
    platforms = [ "x86_64-linux" ];
  };
}
