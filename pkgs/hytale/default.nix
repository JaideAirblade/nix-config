# Hytale Launcher — official launcher for Hytale (not in nixpkgs).
# https://hytale.com
#
# Adapted from forkprince/nur-packages (pkgs/hytale) which itself was
# taken from nixpkgs PR #479368 (gepbird's buildFHSEnv conversion).
# Inlined the version data so we don't depend on forkprince's NUR
# helper library (lib.helper.read / lib.helper.getPlatform).
#
# The launcher is a pre-built binary that expects an FHS layout, so we
# wrap it in buildFHSEnv with the libraries it needs at runtime.
{
  lib,
  stdenv,
  fetchurl,
  unzip,
  buildFHSEnv,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  gtk3,
  nss,
  libsecret,
  libsoup_3,
  gdk-pixbuf,
  glib,
  glib-networking,
  webkitgtk_4_1,
  xdg-utils,
  openssl,
  SDL2,
  libX11,
  libXcursor,
  libXext,
  libXi,
  libXinerama,
  libXrandr,
  libXxf86vm,
  wayland,
  libxkbcommon,
  libdecor,
  alsa-lib,
  libpulseaudio,
  hicolor-icon-theme,
  adwaita-icon-theme,
  gst_all_1,
}: let
  version = "2026.07.07-325d709";
  pname = "hytale-launcher";

  src = fetchurl {
    url = "https://launcher.hytale.com/builds/release/linux/amd64/hytale-launcher-${version}.zip";
    hash = "sha256-qC5q+5DRkl0jqmPRdWlcZ9n0sYKQdwmPncL/It9FhMw=";
  };

  unwrapped = stdenv.mkDerivation {
    pname = "${pname}-unwrapped";
    inherit version src;

    sourceRoot = ".";

    nativeBuildInputs = [
      makeWrapper
      unzip
      copyDesktopItems
    ];

    desktopItems = [
      (makeDesktopItem {
        name = "hytale-launcher";
        exec = "hytale-launcher";
        desktopName = "Hytale Launcher";
        categories = [ "Game" ];
        terminal = false;
      })
    ];

    dontBuild = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
      install -Dm755 "hytale-launcher" "$out/bin/hytale-launcher"
      runHook postInstall
    '';

    meta = {
      description = "Official launcher for Hytale";
      homepage = "https://hytale.com";
      license = lib.licenses.unfreeRedistributable;
      maintainers = with lib.maintainers; [ ];
      mainProgram = "hytale-launcher";
      platforms = [ "x86_64-linux" ];
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  };
in
  buildFHSEnv {
    name = pname;
    inherit version;

    targetPkgs = pkgs: (with pkgs; [
      unwrapped
      gtk3
      nss
      libsecret
      libsoup_3
      gdk-pixbuf
      glib
      glib-networking
      webkitgtk_4_1
      xdg-utils
      mesa
      libglvnd
      libdrm
      icu
      openssl
      SDL2
      libX11
      libXcursor
      libXrandr
      libXext
      libXi
      libXinerama
      libXxf86vm
      wayland
      libxkbcommon
      libdecor
      alsa-lib
      libpulseaudio
      hicolor-icon-theme
      adwaita-icon-theme
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good
      gst_all_1.gst-plugins-bad
      gst_all_1.gst-plugins-ugly
      gst_all_1.gst-libav
    ]);

    # WEBKIT_DISABLE_DMABUF_RENDERER=1 — WebKitGTK's DMA-BUF renderer
    # crashes on wlroots-based compositors (Mango). Same fix as Octarine.
    #
    # GST_PLUGIN_PATH — WebKitGTK uses GStreamer for image/media decoding,
    # but buildFHSEnv doesn't wire up the plugin paths automatically.
    # Without gst-plugins-good, images show as broken icons and rich
    # content (patch notes, banners) fails to render. We point at every
    # plugin dir so GStreamer finds them inside the FHS sandbox.
    #
    # GIO_EXTRA_MODULES — glib-networking's TLS module so WebKitGTK can
    # load HTTPS resources (patch notes are fetched over HTTPS).
    #
    # TMPDIR — the launcher patches game files by downloading to a temp
    # dir then rename()ing them into the install dir. /tmp is tmpfs (RAM)
    # while ~/.local/share/Hytale is on disk, so rename() fails with
    # EXDEV ("invalid cross-device link"). Pointing TMPDIR at a dir on
    # the same filesystem as the install dir makes rename() work.
    profile = ''
      export WEBKIT_DISABLE_DMABUF_RENDERER=1
      export __NV_DISABLE_EXPLICIT_SYNC=1
      export GST_PLUGIN_PATH=${lib.makeSearchPathOutput "lib/gstreamer-1.0" "lib/gstreamer-1.0" [
        gst_all_1.gst-plugins-base
        gst_all_1.gst-plugins-good
        gst_all_1.gst-plugins-bad
        gst_all_1.gst-plugins-ugly
        gst_all_1.gst-libav
      ]}
      export GIO_EXTRA_MODULES=${glib-networking}/lib/gio/modules
      export TMPDIR=$HOME/.local/share/Hytale/.tmp
      mkdir -p "$TMPDIR"
    '';

    runScript = "hytale-launcher";

    extraInstallCommands = ''
      mkdir -p "$out/share/applications"
      ln -s "${unwrapped}/share/applications/hytale-launcher.desktop" "$out/share/applications/"
    '';

    inherit (unwrapped) meta;
  }