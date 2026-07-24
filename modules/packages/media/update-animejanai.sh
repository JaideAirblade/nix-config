#!/usr/bin/env bash
# update-animejanai — fetches the latest AnimeJaNai release version from GitHub,
# downloads the Linux tar.zst + TensorRT runtime component, computes sha256
# hashes, and patches animejanai.nix with the new version + hashes.
#
# Usage: ./update-animejanai.sh [version]
#   If version is omitted, fetches the latest from the GitHub API.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NIX_FILE="$SCRIPT_DIR/animejanai.nix"

# --- Determine version ---
if [ $# -ge 1 ]; then
  VERSION="$1"
else
  echo "Fetching latest AnimeJaNai release..."
  VERSION=$(curl -fsSL "https://api.github.com/repos/the-database/mpv-AnimeJaNai/releases/latest" \
    | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
  if [ -z "$VERSION" ]; then
    echo "Error: could not fetch latest version from GitHub API" >&2
    exit 1
  fi
fi

echo "Version: $VERSION"

# --- Check current version ---
CURRENT=$(grep -oP 'version = "\K[^"]+' "$NIX_FILE" || echo "")
if [ "$CURRENT" = "$VERSION" ]; then
  echo "Already at $VERSION — nothing to do."
  exit 0
fi
echo "Updating from ${CURRENT:-none} → $VERSION"

# --- Download files and compute hashes ---
TMPDIR=$(mktemp -d -t animejanai-update-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

TAR_URL="https://github.com/the-database/mpv-upscale-2x_animejanai/releases/download/${VERSION}/mpv-upscale-2x_animejanai-v${VERSION}-linux-x64.tar.zst"
TRT_URL="https://github.com/the-database/mpv-AnimeJaNai/releases/download/${VERSION}/component-trt-runtime-linux-x64.7z"
PTX_URL="https://github.com/the-database/mpv-AnimeJaNai/releases/download/${VERSION}/component-trt-ptx-linux-x64.7z"

echo "Downloading Linux portable release..."
curl -fSL -o "$TMPDIR/animejanai.tar.zst" "$TAR_URL"
TAR_HASH=$(sha256sum "$TMPDIR/animejanai.tar.zst" | cut -d' ' -f1)
echo "  sha256: $TAR_HASH"

echo "Downloading TensorRT runtime component..."
curl -fSL -o "$TMPDIR/trt-runtime.7z" "$TRT_URL"
TRT_HASH=$(sha256sum "$TMPDIR/trt-runtime.7z" | cut -d' ' -f1)
echo "  sha256: $TRT_HASH"

echo "Downloading TensorRT PTX component..."
curl -fSL -o "$TMPDIR/trt-ptx.7z" "$PTX_URL"
PTX_HASH=$(sha256sum "$TMPDIR/trt-ptx.7z" | cut -d' ' -f1)
echo "  sha256: $PTX_HASH"

# --- Patch animejanai.nix ---
echo "Patching $NIX_FILE..."

# Update version
sed -i "s|version = \".*\";|version = \"${VERSION}\";|" "$NIX_FILE"

# Update tar.zst hash
sed -i "/mpv-upscale-2x_animejanai-v.*linux-x64.tar.zst/,/sha256 =/ {
  s|sha256 = \".*\";|sha256 = \"${TAR_HASH}\";|
}" "$NIX_FILE"

# Update TRT runtime hash
sed -i "/component-trt-runtime-linux-x64.7z/,/sha256 =/ {
  s|sha256 = \".*\";|sha256 = \"${TRT_HASH}\";|
}" "$NIX_FILE"

# Update TRT PTX hash
sed -i "/component-trt-ptx-linux-x64.7z/,/sha256 =/ {
  s|sha256 = \".*\";|sha256 = \"${PTX_HASH}\";|
}" "$NIX_FILE"

echo ""
echo "Done! Updated animejanai.nix to v$VERSION"
echo "Run: sudo nixos-rebuild switch"
echo ""
echo "Verify with:"
echo "  nix eval .#nixosConfigurations.UwU.config.system.build.toplevel.drvPath"