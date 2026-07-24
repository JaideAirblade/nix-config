#!/usr/bin/env python3
"""
torrent-stream: Stream a magnet link or .torrent file in mpv.

Uses libtorrent-rasterbar for sequential download (prioritizes early pieces
so playback can start ASAP). mpv plays the file directly as it downloads.

Usage:
    torrent-stream <magnet-link-or-.torrent-file>

Invoked automatically by the mpv wrapper when given a magnet: URL or .torrent file.
"""

import sys
import os
import time
import tempfile
import subprocess
import shutil
from pathlib import Path

try:
    import libtorrent as lt
except ImportError:
    print("Error: libtorrent-rasterbar not installed.", file=sys.stderr)
    print("Add python3.withPackages (p: [ p.libtorrent-rasterbar ]) to your NixOS config.", file=sys.stderr)
    sys.exit(1)


def human_size(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024
    return f"{n:.1f}TB"


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <magnet-link-or-.torrent-file>", file=sys.stderr)
        sys.exit(1)

    source = sys.argv[1]

    # Set up temp download directory
    tmpdir = tempfile.mkdtemp(prefix="torrent-stream-")
    atp = lt.add_torrent_params()

    if source.startswith("magnet:"):
        atp = lt.parse_magnet_uri(source)
    elif os.path.isfile(source):
        info = lt.torrent_info(source)
        atp.ti = info
    else:
        print(f"Error: not a magnet link or .torrent file: {source}", file=sys.stderr)
        sys.exit(1)

    atp.save_path = tmpdir

    # Create session
    settings = {
        "enable_dht": True,
        "enable_lsd": True,
        "enable_natpmp": True,
        "enable_upnp": True,
    }
    s = lt.session(settings)
    h = s.add_torrent(atp)

    print(f"Torrent: {h.status().name}")
    print(f"Saving to: {tmpdir}")

    # Wait for metadata (magnet links need this)
    if not h.status().has_metadata:
        print("Fetching metadata...", end="", flush=True)
        while not h.status().has_metadata:
            time.sleep(0.5)
            print(".", end="", flush=True)
        print(" done")

    # Get file info — pick the largest file (usually the video)
    tor = h.torrent_file()
    files = tor.files()
    largest_idx = 0
    largest_size = 0
    for i in range(files.num_files()):
        sz = files.file_size(i)
        if sz > largest_size:
            largest_size = sz
            largest_idx = i

    file_path = os.path.join(tmpdir, files.file_path(largest_idx))
    file_name = os.path.basename(file_path)
    print(f"Streaming: {file_name} ({human_size(largest_size)})")

    # Prioritize the largest file, set sequential download for streaming
    priorities = [0] * files.num_files()
    priorities[largest_idx] = 7  # high priority for our file
    h.prioritize_files(priorities)

    # Enable sequential download — prioritizes early pieces so playback can start
    h.set_flags(lt.torrent_flags.sequential_download, lt.torrent_flags.sequential_download)

    # Request the first few pieces urgently to kickstart playback
    num_pieces = tor.num_pieces()
    piece_length = tor.piece_length()
    urgent_pieces = min(num_pieces, max(10, (10 * 1024 * 1024) // piece_length))
    for i in range(urgent_pieces):
        h.piece_priority(i, 7)

    # Wait for peers to connect
    print("Connecting to peers...", end="", flush=True)
    while True:
        s_st = h.status()
        n_peers = s_st.num_peers
        if n_peers > 0:
            break
        time.sleep(0.5)
        print(".", end="", flush=True)
    print(f" connected ({n_peers} peers)")

    # Wait for enough data at the start of the file for mpv to begin playback
    file_offset = files.file_offset(largest_idx) // piece_length
    needed_pieces = min(urgent_pieces, num_pieces - file_offset)
    print(f"Waiting for first {needed_pieces} pieces...", end="", flush=True)
    while True:
        pieces = h.status().pieces
        have = sum(1 for i in range(file_offset, file_offset + needed_pieces)
                   if i < len(pieces) and pieces[i])
        if have >= needed_pieces:
            break
        time.sleep(0.5)
        print(f"\rWaiting for first {needed_pieces} pieces... ({have}/{needed_pieces})",
              end="", flush=True)
    print(" ready")

    # Launch mpv on the file
    print(f"\nLaunching mpv on {file_path}")
    print(f"Downloaded so far: {human_size(h.status().total_wanted_done)}")

    mpv = subprocess.Popen(["mpv", "--force-seekable=yes", file_path])
    mpv.wait()

    # Cleanup
    print("mpv exited, cleaning up...")
    mpv_ret = mpv.returncode
    s.remove_torrent(h)
    shutil.rmtree(tmpdir, ignore_errors=True)
    sys.exit(mpv_ret)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nInterrupted, cleaning up...", file=sys.stderr)
        sys.exit(130)