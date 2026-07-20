# Betterbird — pre-built binary from upstream (not in nixpkgs, removed due to insufficient maintainers)
# https://www.betterbird.eu/downloads/
# Based on community derivation by nokihe on NixOS Discourse
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  patchelfUnstable,
  wrapGAppsHook3,
  alsa-lib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "betterbird";
  version = "140.12.0esr-bb24";

  src = fetchurl {
    url = "https://www.betterbird.eu/downloads/LinuxArchive/betterbird-${finalAttrs.version}.en-US.linux-x86_64.tar.xz";
    hash = "sha256-ChJWJKS7y8NxFmVBtZtD+yRc5jMxo0HN7AaWmUl7RuA=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    patchelfUnstable
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
  ];

  # Thunderbird uses "relrhack" to manually process relocations from a fixed offset
  patchelfFlags = ["--no-clobber-old-sections"];

  strictDeps = true;

  postPatch = ''
    # Don't download updates from Mozilla directly
    echo 'pref("app.update.auto", "false");' >> defaults/pref/channel-prefs.js
  '';

  installPhase = ''
    runHook preInstall

    appdir="$out/usr/lib/betterbird-bin-${finalAttrs.version}"

    mkdir -p "$appdir"
    cp -r ./* "$appdir"

    mkdir -p "$out/bin"
    ln -s "$appdir/betterbird" "$out/bin/betterbird"

    # wrapThunderbird expects "$out/lib" instead of "$out/usr/lib"
    ln -s "$out/usr/lib" "$out/lib"

    # ---------- Desktop entry ----------
    mkdir -p "$out/share/applications"
    cat > "$out/share/applications/betterbird.desktop" <<EOF
    [Desktop Entry]
    Name=Betterbird
    GenericName=Mail Client
    Comment=Fine-tuned version of Mozilla Thunderbird
    Exec=betterbird %u
    Terminal=false
    Type=Application
    Icon=betterbird
    Categories=Network;Email;GTK;
    MimeType=message/rfc822;x-scheme-handler/mailto;
    StartupWMClass=Betterbird
    EOF

    # ---------- Icons (symlinks) ----------
    icon_src_dir="$appdir/chrome/icons/default"
    if [ -d "$icon_src_dir" ]; then
      for size in 16 22 24 32 48 64 128 256; do
        icon_src="$icon_src_dir/default''${size}.png"
        if [ -f "$icon_src" ]; then
          icon_dest_dir="$out/share/icons/hicolor/''${size}x''${size}/apps"
          mkdir -p "$icon_dest_dir"
          ln -s "$icon_src" "$icon_dest_dir/betterbird.png"
        fi
      done
      if [ -f "$icon_src_dir/default.svg" ]; then
        icon_dest_dir="$out/share/icons/hicolor/scalable/apps"
        mkdir -p "$icon_dest_dir"
        ln -s "$icon_src_dir/default.svg" "$icon_dest_dir/betterbird.svg"
      fi
    fi

    runHook postInstall
  '';

  meta = {
    changelog = "https://www.betterbird.eu/releasenotes/";
    description = "Betterbird is a fine-tuned version of Mozilla Thunderbird, Thunderbird on steroids, if you will.";
    homepage = "https://www.betterbird.eu";
    mainProgram = "betterbird";
    sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    license = lib.licenses.mpl20;
    maintainers = with lib.maintainers; [];
    platforms = ["x86_64-linux"];
  };
})