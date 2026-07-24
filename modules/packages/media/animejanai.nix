# AnimeJaNai — real-time AI anime upscaling for mpv (NVIDIA TensorRT)
#
# This module downloads the Linux portable release + TensorRT PTX runtime,
# merges them into a single tree, and wraps the launcher in an FHS env
# so the bundled mpv fork (with vf_animejanai filter) can find its libs.
#
# Only makes sense on UwU (RTX 3080). The work laptop has no NVIDIA GPU.
#
# Usage: mpv-animejanai <file-or-url>
# Profiles: Shift+1=Quality, Shift+2=Balanced (default, RTX 3080), Shift+3=Performance
# Stats: Ctrl+J | Update: Ctrl+U | Manager: Ctrl+E
{ pkgs, lib, config, ... }:

let
  version = "3.5.0";

  # Main portable release (mpv fork + ONNX models + aji inference + scripts)
  animejanaiSrc = pkgs.fetchurl {
    url = "https://github.com/the-database/mpv-upscale-2x_animejanai/releases/download/${version}/mpv-upscale-2x_animejanai-v${version}-linux-x64.tar.zst";
    sha256 = "650f67e29c5aa84adf5185910183bbff6897913ec2fc38e686173c093c5bc3ca";
  };

  # TensorRT 11 runtime libs (libnvinfer.so, libcudart.so, trtexec, etc.)
  # These are the core TRT libraries needed by libaji_trt.so.
  trtRuntimeSrc = pkgs.fetchurl {
    url = "https://github.com/the-database/mpv-AnimeJaNai/releases/download/${version}/component-trt-runtime-linux-x64.7z";
    sha256 = "a524f799bd9313eb6afbebb6febba53d7e3f52b962a2ffaa69a6830ae3465dec";
  };

  # TensorRT 11 PTX kernel resource — PTX is forward-compatible across all
  # NVIDIA architectures (JIT-compiled at first run). The runtime component
  # only ships pre-built kernels for specific GPU architectures and missed
  # the RTX 3080 (Ampere SM86). PTX builds engines for any GPU on first play.
  trtPtxSrc = pkgs.fetchurl {
    url = "https://github.com/the-database/mpv-AnimeJaNai/releases/download/${version}/component-trt-ptx-linux-x64.7z";
    sha256 = "4fae5f05229c26d9af8aee93a89da7b8253fa01f288c81e980dc6e9785916a43";
  };

  # Merge the main tarball + TRT runtime + TRT PTX kernels into a single tree.
  # Runtime provides libnvinfer.so, libcudart.so, trtexec.
  # PTX provides libnvinfer_builder_resource_ptx.so (GPU kernel resource for JIT).
  animejanaiTree = pkgs.runCommand "animejanai-${version}" {
    nativeBuildInputs = [ pkgs.zstd pkgs.p7zip ];
  } ''
    mkdir -p $out

    # Extract main tarball
    tar --zstd -xf ${animejanaiSrc} --strip-components=1 -C $out

    # Extract TRT runtime on top (adds libnvinfer.so, libcudart.so, trtexec)
    7z x -y ${trtRuntimeSrc} -o/tmp/trt-runtime >/dev/null
    cp -rT /tmp/trt-runtime/animejanai/inference $out/animejanai/inference
    rm -rf /tmp/trt-runtime

    # Extract TRT PTX kernels on top (adds libnvinfer_builder_resource_ptx.so)
    7z x -y ${trtPtxSrc} -o/tmp/trt-ptx >/dev/null
    cp -rT /tmp/trt-ptx/animejanai/inference $out/animejanai/inference
    rm -rf /tmp/trt-ptx

    # Create a minimal fontconfig that doesn't include the system's conf.d
    # (the bundled mpv's older libfontconfig can't parse newer XML attributes).
    # Points to the FHS env's /usr/share/fonts (populated by fontconfig deps).
    cat > $out/portable_config/fonts.conf <<'FONTS'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <dir>/usr/share/fonts</dir>
  <dir>/usr/local/share/fonts</dir>
  <dir>~/.local/share/fonts</dir>
  <dir>~/.fonts</dir>
  <cachedir>~/.cache/fontconfig</cachedir>
  <match target="font"><edit name="autohint"><bool>false</bool></edit></match>
  <match target="font"><edit name="hintstyle"><const>hintslight</const></edit></match>
  <match target="font"><edit name="antialias"><bool>true</bool></edit></match>
  <match target="font"><edit name="rgba"><const>rgb</const></edit></match>
  <match target="font"><edit name="lcdfilter"><const>lcddefault</const></edit></match>
  <!-- Generic family aliases so sans-serif/serif/monospace resolve -->
  <match target="pattern"><test name="family"><string>sans-serif</string></test><edit name="family" mode="assign" binding="strong"><string>DejaVu Sans</string></edit></match>
  <match target="pattern"><test name="family"><string>serif</string></test><edit name="family" mode="assign" binding="strong"><string>DejaVu Serif</string></edit></match>
  <match target="pattern"><test name="family"><string>monospace</string></test><edit name="family" mode="assign" binding="strong"><string>DejaVu Sans Mono</string></edit></match>
</fontconfig>
FONTS
  '';

  # FHS wrapper — the bundled mpv binary has interpreter /lib64/ld-linux-x86-64.so.2
  # and links against bundled .so files. FHS env provides the standard paths.
  mpvAnimeJaNai = pkgs.buildFHSEnv {
    name = "mpv-animejanai";
    targetPkgs = pkgs: with pkgs; [
      # System libs the bundled mpv needs that aren't in the tarball
      gcc-unwrapped.lib  # libstdc++.so.6 for TRT libs
      libgcc           # libgcc_s.so
      zlib             # libz.so.1
      alsa-lib         # libasound.so.2
      expat            # libexpat.so.1
      fontconfig       # libfontconfig.so.1
      freetype         # libfreetype.so.6
      libx11           # libX11.so.6
      libxext          # libXext.so.6
      libxfixes        # libXfixes.so.3
      libxscrnsaver    # libXss.so.1
      libxpresent      # libXpresent.so.1
      libxrandr        # libXrandr.so.2
      libxv            # libXv.so.1
      libpulseaudio    # libpulse.so.0
      libjpeg          # libjpeg.so.8
      libuchardet      # libuchardet.so.0
      libbluray        # libbluray.so.2
      libcdio          # libcdio.so.19
      libcdio-paranoia # libcdio_paranoia.so.2
      libdvdnav        # libdvdnav.so.4
      lcms2            # liblcms2.so.2
      vulkan-loader    # vulkan
      libGL            # libEGL.so.1, libGL.so.1
      libdrm           # libdrm.so.2
      wayland          # libwayland
      pipewire         # pipewire for audio
      linuxPackages.nvidia_x11  # libcuda.so, libnvidia-encode, etc.
      # SSL/TLS — bundled ffmpeg lacks a TLS backend, so HTTPS streams fail.
      # Providing openssl lets ffmpeg's runtime dlopen find a TLS library.
      openssl
      # ICU — the AnimeJaNaiUpdater (.NET) crashes without libicu.
      icu
    ];
    # The bundled mpv ships its own copies of most libs in $out/mpv/.
    # We set LD_LIBRARY_PATH so the bundled libs are found first, then
    # the FHS system libs fill in the gaps.
    runScript = pkgs.writeShellScript "mpv-animejanai-launch" ''
      HERE="${animejanaiTree}"
      export LD_LIBRARY_PATH="$HERE/mpv:$HERE/animejanai/inference:/run/opengl-driver/lib:$LD_LIBRARY_PATH"
      # Use a minimal fontconfig that avoids the system's conf.d files
      export FONTCONFIG_FILE="$CFG_DIR/fonts.conf"

      # The nix store is read-only, but AnimeJaNai needs to write:
      #   - TRT engine cache files (*.engine) in the onnx model dir
      #   - stats log (currentanimejanai.log)
      #   - engine build logs in the onnx model dir
      #   - screenshots
      #   - watch-later / saved positions
      #
      # Replicate the original directory structure in a writable data dir:
      #   $DATA_DIR/
      #     portable_config/   (--config-dir, ~~ expands here)
      #     animejanai/         (~~/../animejanai/ — sibling of portable_config)
      #       onnx/            (writable — TRT builds .engine files here)
      #       inference/       (symlink to nix store — read-only libs)
      #       animejanai.conf  (writable — user-customizable profiles)
      #       rife/            (writable — RIFE model dir)
      # This way ~~/../animejanai/ paths resolve naturally without sed patches.
      DATA_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/animejanai"
      CFG_DIR="$DATA_DIR/portable_config"
      AJ_DIR="$DATA_DIR/animejanai"

      # First run: set up the writable tree
      if [ ! -d "$CFG_DIR/scripts" ]; then
        mkdir -p "$CFG_DIR/scripts" "$CFG_DIR/shaders" "$CFG_DIR/screenshots"
        mkdir -p "$AJ_DIR/onnx" "$AJ_DIR/rife"

        # Copy config files (small, editable)
        cp "$HERE/portable_config/mpv.conf" "$CFG_DIR/"
        cp "$HERE/portable_config/input.conf" "$CFG_DIR/"
        cp "$HERE/portable_config/saved-props.json" "$CFG_DIR/" 2>/dev/null || true
        cp "$HERE/portable_config/settings.xml" "$CFG_DIR/" 2>/dev/null || true

        # Copy ONNX models (TRT builds .engine cache files next to them)
        cp "$HERE/animejanai/onnx/"*.onnx "$AJ_DIR/onnx/"

        # Copy animejanai.conf (user-customizable profiles)
        cp "$HERE/animejanai/animejanai.conf" "$AJ_DIR/"

        # Symlink inference libs (read-only is fine)
        ln -sf "$HERE/animejanai/inference" "$AJ_DIR/inference"
      fi

      # Always update scripts + shaders + managed conf from nix store
      # (so rebuilds pick up new versions without manual cleanup)
      cp "$HERE/portable_config/scripts/"*.lua "$CFG_DIR/scripts/"
      cp "$HERE/portable_config/shaders/"*.hook "$CFG_DIR/shaders/"
      cp "$HERE/portable_config/mpv-animejanai.conf" "$CFG_DIR/"
      cp "$HERE/portable_config/input-animejanai.conf" "$CFG_DIR/"
      cp "$HERE/portable_config/fonts.conf" "$CFG_DIR/"

      # The bundled mpv's ffmpeg was compiled without TLS, so it can't open
      # HTTPS URLs. For URL arguments, stream via yt-dlp through a FIFO so mpv
      # reads from a local pipe instead of trying to open the network URL.
      YTDLP="${pkgs.yt-dlp}/bin/yt-dlp"

      args=()
      fifos=()
      pids=()
      for arg in "$@"; do
        case "$arg" in
          http://*|https://*)
            # URL — pipe yt-dlp best quality output through a FIFO
            fifo=$(mktemp -u -t animejanai-fifo-XXXXXX)
            mkfifo "$fifo"
            # Use best format up to 1080p for upscaling (the whole point of
            # AnimeJaNai is to upscale, so 1080p source is ideal; 4K source
            # would need downscaling first and wastes bandwidth).
            "$YTDLP" -f "bestvideo[height<=?1080]+bestaudio/best[height<=?1080]/best" \
              -o - "$arg" >"$fifo" &
            pids+=($!)
            fifos+=("$fifo")
            args+=("$fifo")
            ;;
          *)
            args+=("$arg")
            ;;
        esac
      done

      # Launch mpv with the writable config dir (all paths point to $DATA_DIR)
      "$HERE/mpv/mpv" --config-dir="$CFG_DIR" \
        --script-opts=ytdl_hook-ytdl_path="$YTDLP" \
        "''${args[@]}"
      mpv_exit=$?

      # Cleanup
      for pid in "''${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
      for f in "''${fifos[@]}"; do rm -f "$f"; done
      exit $mpv_exit
    '';
  };

in
{
  config = lib.mkIf (config.networking.hostName == "UwU") {
    environment.systemPackages = [
      mpvAnimeJaNai
    ];
  };
}