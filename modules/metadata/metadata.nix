# Metadata tools — `meta` and `scrub` wrapper scripts.
#
# `meta <file>`  — shows file type (magic bytes), EXIF/metadata, and
#   media info (codec, resolution, etc.) for any file. Combines:
#   - `file` (magic byte identification — "this is a PE32 exe", "this is a JPEG")
#   - `exiftool` (EXIF/IPTC/XMP metadata — camera model, GPS, timestamps)
#   - `mediainfo` (video/audio technical info — codec, bitrate, duration)
#
# `scrub <file>` — removes metadata from supported files. Uses:
#   - `mat2` for images, audio, video, documents (PDF, Office, epub)
#   - `exiftool -all=` for raw EXIF stripping on formats mat2 doesn't support
#   - For exe/binary files: warns that metadata can't be scrubbed (the PE
#     headers contain compile timestamps etc. but can't be safely removed
#     without breaking the executable)
#
# Usage:
#   info ./photo.jpg          # see all metadata
#   info ./game.exe           # see file type + PE headers
#   info ./video.mp4          # see codec, bitrate, EXIF
#   scrub ./photo.jpg         # strip all metadata (creates .cleaned copy)
#   scrub ./photo.jpg --inplace  # strip metadata in-place
{ pkgs, ... }:

{
  environment.systemPackages = [
    # meta — unified metadata viewer
    (pkgs.writeShellScriptBin "meta" ''
      #!/bin/sh
      # meta <file> — show file type + all metadata
      if [ -z "$1" ]; then
        echo "Usage: meta <file>"
        echo "Shows file type (magic bytes), EXIF/metadata, and media info."
        exit 1
      fi

      f="$1"
      if [ ! -f "$f" ]; then
        echo "Error: '$f' not found or not a regular file"
        exit 1
      fi

      echo "═══════════════════════════════════════════════════════════════"
      echo "  File: $f"
      echo "═══════════════════════════════════════════════════════════════"
      echo ""

      # 1. File type (magic bytes)
      echo "── File Type (magic bytes) ────────────────────────────────────"
      file "$f"
      echo ""

      # 2. EXIF/metadata (exiftool handles most formats)
      echo "── Metadata (exiftool) ───────────────────────────────────────"
      exiftool "$f" 2>/dev/null
      echo ""

      # 3. Media info (for video/audio files — codec, bitrate, etc.)
      # Only run mediainfo if the file is a video/audio format
      ftype=$(file -b --mime-type "$f" 2>/dev/null)
      case "$ftype" in
        video/*|audio/*)
          echo "── Media Info (mediainfo) ──────────────────────────────────"
          mediainfo "$f" 2>/dev/null
          echo ""
          ;;
      esac

      echo "═══════════════════════════════════════════════════════════════"
    '')

    # scrub — metadata remover
    (pkgs.writeShellScriptBin "scrub" ''
      #!/bin/sh
      # scrub <file> [--inplace] — remove metadata from file
      #
      # By default creates a cleaned copy (original is preserved).
      # Use --inplace to modify the original file.
      #
      # Supported: images (JPEG, PNG, GIF, BMP, TIFF, WebP, HEIC),
      # audio (MP3, FLAC, OGG, WAV, AIFF), video (MP4, AVI, WMV),
      # documents (PDF, DOCX, XLSX, PPTX, ODT, ODS, EPUB),
      # archives (ZIP, TAR), torrents, HTML, SVG, text.
      #
      # Not supported: exe, dll, binary blobs (metadata is embedded in
      # PE headers and can't be removed without breaking the executable).

      inplace=false
      files=""
      for arg in "$@"; do
        if [ "$arg" = "--inplace" ] || [ "$arg" = "-i" ]; then
          inplace=true
        else
          files="$files $arg"
        fi
      done

      if [ -z "$files" ]; then
        echo "Usage: scrub <file> [--inplace]"
        echo "  --inplace / -i  : modify the original file (no backup)"
        echo ""
        echo "Supported: images, audio, video, PDF, Office docs, epub, zip, tar, torrent"
        echo "Not supported: exe, dll, binary blobs"
        exit 1
      fi

      for f in $files; do
        if [ ! -f "$f" ]; then
          echo "Error: '$f' not found"
          continue
        fi

        ftype=$(file -b --mime-type "$f" 2>/dev/null)
        echo "── Scrubbing: $f ($ftype) ──"

        # Try mat2 first (best metadata scrubber — handles most formats)
        if [ "$inplace" = "true" ]; then
          mat2 --inplace "$f" 2>&1
        else
          mat2 "$f" 2>&1
        fi
        mat2_exit=$?

        if [ $mat2_exit -ne 0 ]; then
          # mat2 doesn't support this format — try exiftool as fallback
          echo "  mat2 doesn't support $ftype, trying exiftool..."
          if exiftool -all= -overwrite_original "$f" 2>/dev/null | grep -q "updated"; then
            echo "  ✓ Metadata stripped via exiftool"
          else
            echo "  ✗ Cannot scrub metadata from this file type ($ftype)"
            echo "    For exe/binary files: PE headers contain compile timestamps"
            echo "    and other metadata that can't be safely removed."
          fi
        else
          echo "  ✓ Metadata stripped via mat2"
        fi
        echo ""
      done
    '')
  ];
}