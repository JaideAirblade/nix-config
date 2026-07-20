{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # --- Playback ---
    (mpv.override {
      scripts = with mpvScripts; [
        uosc
        sponsorblock
        quality-menu
        thumbfast
        mpris
        autoload
        autocrop
      ];
    })
    yt-dlp

    # --- Transcoding & processing ---
    ffmpeg
    ffmpegthumbnailer

    # --- Image ---
    imagemagick
    qimgv
  ];
}