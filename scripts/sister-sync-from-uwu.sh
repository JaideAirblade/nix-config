#!/usr/bin/env bash
# sister-sync-from-uwu.sh — Copy jaide's home dir from UwU to Luna-Server.
#
# Usage:
#   just sister-sync              # dry-run
#   just sister-sync-apply        # actually copy
#   ./scripts/sister-sync-from-uwu.sh [--apply]
#
# What it copies:
#   jaide's full /home/jaide from UwU (the desktop at 100.119.53.51), with
#   the rules in scripts/uwu-rsync-excludes.txt applied. Excludes are
#   extensive: games, game caches, browser caches, rebuildable artifacts,
#   Steam entirely, etc.
#
# What it does NOT touch:
#   - Pictures/Wallpapers is INCLUDED (634M, jaide wants wallpapers)
#   - .config/* Firefox user data is INCLUDED
#   - .hermes/{skills,plugins,cron,profiles} is INCLUDED
#   - .nix-defexpr and Nix profiles are INCLUDED (Nix needs them)
#
# Ownership:
#   Local rsync runs as root (so it can write into /home/jaide which is
#   mode 750 owned by jaide:jaide). --chown=jaide:jaide makes the new files
#   land as jaide:jaide, matching the originals on UwU.
#
# Remote:
#   Uses --rsync-path="sudo rsync" so the remote rsync runs as root and
#   can read jaide's mode-700 config dirs. luna (not jaide) SSHes in
#   because luna has the rendered Tailscale identity; sudo on UwU is
#   NOPASSWD for luna.
#
# Idempotency:
#   Without --delete, rsync only adds/overwrites — never deletes jaide's
#   existing files on the server. If jaide has anything locally that's
#   NOT on UwU (because it was created on the server), it stays untouched.

set -euo pipefail

apply=0
for arg in "$@"; do
    case "$arg" in
        --apply) apply=1 ;;
        --dry-run) apply=0 ;;
        -h|--help)
            sed -n '2,28p' "$0"
            exit 0
            ;;
    esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exclude_file="${script_dir}/uwu-rsync-excludes.txt"

if [ ! -f "$exclude_file" ]; then
    echo "FATAL: exclude file not found: $exclude_file" >&2
    exit 1
fi

if [ "$apply" = 0 ]; then
    echo "DRY RUN: no files will be modified. Pass --apply to actually copy."
    rsync_args=( -avzn )
else
    echo "APPLY MODE: files will be written into /home/jaide on this host."
    rsync_args=( -avz --info=progress2 )
fi

# Always include --chown=jaide:jaide so files land as jaide, not root.
rsync_args+=( --chown=jaide:jaide )

# Use luna's Tailscale identity for SSH.
ssh_args=( -i /home/luna/.ssh/id_ed25519
           -o BatchMode=yes
           -o StrictHostKeyChecking=accept-new
           -l luna )

# Remote runs rsync as root so it can read mode-700 config dirs.
rsync_path="sudo rsync"

sudo rsync "${rsync_args[@]}" \
    --exclude-from="$exclude_file" \
    -e "ssh ${ssh_args[*]}" \
    --rsync-path="$rsync_path" \
    'luna@100.119.53.51:/home/jaide/' \
    '/home/jaide/' \
    2>&1 | tee /tmp/sister-sync-from-uwu.log
