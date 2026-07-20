# Octarine — private, markdown-based note-taking app (Tauri/Rust, not in nixpkgs)
# https://octarine.app
# Arch Linux package from upstream, patched with autoPatchelfHook
#
# Dependencies from the PKGBUILD:
#   gtk3, libappindicator-gtk3, webkit2gtk-4.1, xdotool
#
# Runtime libraries needed (from ldd):
#   libstdc++, libssl/libcrypto, gtk3, gdk-pixbuf, cairo, glib,
#   webkitgtk_4_1, libsoup_3, libayatana-appindicator
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zstd,
  wrapGAppsHook3,
  # Runtime dependencies
  webkitgtk_4_1,
  gtk3,
  glib,
  glib-networking,  # TLS/SSL for GLib networking — without this, WebKitGTK
                    # can't load HTTPS resources and Tauri apps stay stuck
                    # on the loading screen with blank content.
  libsoup_3,
  libayatana-appindicator,
  openssl,
  gcc-unwrapped,  # provides libstdc++.so.6
  desktop-file-utils,  # Tauri setup hook spawns update-desktop-database
  # GStreamer plugins — WebKitGTK uses GStreamer for image/media decoding.
  # Without gst-plugins-good, images don't render (broken image icon).
  # All GStreamer plugins are under gst_all_1 in nixpkgs.
  gst_all_1,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "octarine";
  version = "0.47.4";

  src = fetchurl {
    url = "https://pub-3d35bc018fc54f11bde129e3e73e8002.r2.dev/${finalAttrs.version}/linux/Octarine-bin-${finalAttrs.version}-1-x86_64.pkg.tar.zst";
    hash = "sha256-e9/20tY1epvvUw+2WcDsZVCtDNWWYBtr8dNIBifbE6w=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    zstd
    wrapGAppsHook3
  ];

  buildInputs = [
    webkitgtk_4_1
    gtk3
    glib
    glib-networking  # TLS/SSL support — WebKitGTK needs this to load resources
    libsoup_3
    libayatana-appindicator
    openssl
    gcc-unwrapped  # libstdc++.so.6
    desktop-file-utils  # update-desktop-database at runtime
    # GStreamer plugins — WebKitGTK needs these for image/media decoding.
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-libav
  ];

  # libayatana-appindicator is dlopen'd at runtime (not DT_NEEDED),
  # so autoPatchelfHook's rpath alone isn't enough — dlopen needs LD_LIBRARY_PATH.
  # desktop-file-utils must be in PATH for Tauri's setup hook (update-desktop-database).
  #
  # WEBKIT_DISABLE_DMABUF_RENDERER=1 — WebKitGTK's DMA-BUF renderer crashes on
  # wlroots-based compositors (Mango) with "Error 71 (Protocol error) dispatching
  # to Wayland display" on launch. Disabling the DMA-BUF renderer keeps GPU
  # compositing (so images render correctly) but uses a non-DMABUF path that
  # works on Mango. This is better than WEBKIT_DISABLE_COMPOSITING_MODE=1 (which
  # kills image rendering) or GDK_BACKEND=x11 (which hits NVIDIA GBM errors).
  #
  # GST_PLUGIN_PATH — WebKitGTK uses GStreamer for image/media decoding, but
  # autoPatchelfHook/wrapGAppsHook3 doesn't automatically wire up the plugin
  # paths. Without gst-plugins-good, images show as broken icons. We point
  # GST_PLUGIN_PATH at every plugin dir so GStreamer can find them at runtime.
  preFixup = ''
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libayatana-appindicator ]}
      --prefix PATH : ${lib.makeBinPath [ desktop-file-utils ]}
      --set WEBKIT_DISABLE_DMABUF_RENDERER 1
      --prefix GST_PLUGIN_PATH : ${lib.makeSearchPathOutput "lib/gstreamer-1.0" "lib/gstreamer-1.0" [ gst_all_1.gst-plugins-base gst_all_1.gst-plugins-good gst_all_1.gst-plugins-bad gst_all_1.gst-plugins-ugly gst_all_1.gst-libav ]}
    )
  '';

  strictDeps = true;

  # Arch .pkg.tar.zst extracts with usr/ at top level; keep root as source
  # so installPhase paths (usr/bin/octarine, usr/share/...) match the tree.
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    # Install the binary
    mkdir -p "$out/bin"
    install -Dm755 usr/bin/octarine "$out/bin/octarine"

    # Desktop entry
    mkdir -p "$out/share/applications"
    install -Dm644 usr/share/applications/Octarine.desktop \
      "$out/share/applications/octarine.desktop"

    # Icons
    for dir in usr/share/icons/hicolor/*/apps; do
      size=$(basename "$(dirname "$dir")")
      mkdir -p "$out/share/icons/hicolor/$size/apps"
      cp "$dir"/octarine.png "$out/share/icons/hicolor/$size/apps/octarine.png"
    done

    runHook postInstall
  '';

  meta = {
    changelog = "https://octarine.app/changelog";
    description = "Private, markdown-based note-taking app with a focus on speed, simplicity and data ownership";
    homepage = "https://octarine.app";
    mainProgram = "octarine";
    sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [];
    platforms = ["x86_64-linux"];
  };
})