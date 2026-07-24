{ pkgs, ... }:

let
  # The real mpv with all scripts — exposed as `mpv.real` so the wrapper can find it.
  realMpv = pkgs.mpv.override {
    scripts = with pkgs.mpvScripts; [
      uosc
      sponsorblock
      quality-menu
      thumbfast
      mpris
      autoload
      autocrop
    ];
  };

  # Python env with libtorrent for the torrent-stream script.
  pythonWithLibtorrent = pkgs.python3.withPackages (p: [ p.libtorrent-rasterbar ]);

  # torrent-stream: sequential torrent download → mpv playback.
  # Handles magnet: URLs and .torrent files.
  torrentStream = pkgs.writeShellScriptBin "torrent-stream" ''
    exec ${pythonWithLibtorrent}/bin/python3 ${./torrent-stream.py} "$@"
  '';

  # mpv wrapper: intercepts magnet: URLs and .torrent files, routes them to
  # torrent-stream. Everything else passes through to real mpv unchanged.
  mpvWrapper = pkgs.writeShellScriptBin "mpv" ''
    REAL_MPV="${realMpv}/bin/mpv"
    for arg in "$@"; do
      case "$arg" in
        magnet:*)
          exec ${torrentStream}/bin/torrent-stream "$@"
          ;;
        *.torrent)
          if [ -f "$arg" ]; then
            exec ${torrentStream}/bin/torrent-stream "$@"
          fi
          ;;
      esac
    done
    exec "$REAL_MPV" "$@"
  '';
in
{
  environment.systemPackages = [
    # mpv wrapper (provides `mpv` — intercepts magnet/torrent, delegates rest)
    mpvWrapper
    # Real mpv exposed as `mpv.real` for scripts and fallback
    (pkgs.runCommand "mpv-real" { } ''
      mkdir -p $out/bin
      ln -s ${realMpv}/bin/mpv $out/bin/mpv.real
    '')
    pkgs.yt-dlp

    # --- Torrent streaming (libtorrent for torrent-stream.py) ---
    pythonWithLibtorrent

    # --- Transcoding & processing ---
    pkgs.ffmpeg
    pkgs.ffmpegthumbnailer

    # --- Image ---
    pkgs.imagemagick
    pkgs.qimgv
  ];
}