{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, wrapGAppsHook3
, makeWrapper
, xdg-utils
, coreutils
, alsa-lib
, at-spi2-core
, cairo
, cups
, dbus
, expat
, fontconfig
, freetype
, gdk-pixbuf
, glib
, gtk3
, gtk4
, gsettings-desktop-schemas
, libdrm
, libglvnd
, libpulseaudio
, libva
, libx11
, libxcb
, libxcomposite
, libxcursor
, libxdamage
, libxext
, libxfixes
, libxi
, libxkbcommon
, libxrandr
, libxrender
, libxshmfence
, libxscrnsaver
, libxtst
, mesa
, nspr
, nss
, pango
, pipewire
, qt6
, snappy
, systemd
, util-linuxMinimal
, wayland
, zlib
, krb5
}:

stdenv.mkDerivation rec {
  pname = "helium-bin";
  version = "0.15.5.1";

  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64_linux.tar.xz";
    hash = "sha256-80oe4aarLjEJ2S45OVEqN8/mii8NIwtSXMFYn8GS/Zc=";
  };

  dontConfigure = true;
  dontBuild = true;
  dontWrapQtApps = true;

  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook3
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-core
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    gtk4
    gsettings-desktop-schemas
    libdrm
    libglvnd
    libpulseaudio
    libva
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxkbcommon
    libxrandr
    libxrender
    libxshmfence
    libxscrnsaver
    libxtst
    mesa
    nspr
    nss
    pango
    pipewire
    qt6.qtbase
    snappy
    systemd
    util-linuxMinimal
    wayland
    zlib
    krb5
  ];

  installPhase = ''
    runHook preInstall

    appDir="$out/lib/helium"
    mkdir -p "$appDir" "$out/bin" "$out/share/applications" \
      "$out/share/icons/hicolor/256x256/apps"
    cp -a . "$appDir"

    # Helium ships a Qt 5 compatibility shim alongside its current Qt 6 shim.
    # Keeping both triggers NixOS's mixed-Qt wrapper guard.
    rm -f "$appDir/libqt5_shim.so"

    substituteInPlace "$appDir/helium-wrapper" \
      --replace-fail 'CHROME_VERSION_EXTRA="custom"' 'CHROME_VERSION_EXTRA="NixOS"'

    ln -s "$appDir/helium-wrapper" "$out/bin/helium"
    install -Dm644 "$appDir/helium.desktop" \
      "$out/share/applications/helium.desktop"
    install -Dm644 "$appDir/product_logo_256.png" \
      "$out/share/icons/hicolor/256x256/apps/helium.png"

    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath buildInputs}"
      --prefix PATH : "${lib.makeBinPath [ xdg-utils coreutils ]}"
      --set CHROME_WRAPPER helium
      --add-flags '--ozone-platform=x11'
    )
  '';

  installCheckPhase = ''
    "$out/lib/helium/helium" --version | grep -F "Helium"
  '';

  doInstallCheck = true;

  meta = with lib; {
    description = "Private, fast, and honest Chromium-based web browser";
    homepage = "https://github.com/imputnet/helium-linux";
    license = licenses.gpl3Only;
    mainProgram = "helium";
    platforms = [ "x86_64-linux" ];
  };
}
