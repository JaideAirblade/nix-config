#!/usr/bin/env bash
# edit-snapshot.sh — instant revert for nix-config edits via hard-link snapshots.
#
# Concept: every "edit session" starts with `edit-snapshot.sh save`. The
# script hard-links the current working tree into ~/.cache/luna-edit-snapshots/
# (one snapshot per session, named by timestamp + branch). On revert,
# the snapshot is restored by `rm -rf` + `cp -al`, which is essentially
# instant for typical flake sizes (150 files, ~3MB).
#
# Why hard-links instead of git stash? Git stash works fine, but:
#   - It requires a clean tree OR explicit --keep-index
#   - It only works on git-tracked files (untracked files are excluded)
#   - It doesn't preserve file modes (mtime is preserved, but modes
#     may not be if the user ran chmod)
# Hard-link snapshots:
#   - Work on ANY file in the repo (including untracked, like a fresh
#     .nix file that hasn't been git-added yet — exactly the
#     build-vs-commit race case)
#   - Are O(1) per file (just creates a hard-link, no copy)
#   - Revert is O(n) where n = number of files, but each restore is
#     a single rename() syscall
#
# Usage:
#   edit-snapshot.sh save [label]     # snapshot current state
#   edit-snapshot.sh list             # list snapshots, newest first
#   edit-snapshot.sh revert <id>      # revert to snapshot <id>
#   edit-snapshot.sh last             # show last snapshot id
#   edit-snapshot.sh rm <id>          # delete a snapshot
#   edit-snapshot.sh diff <id>        # show files-different summary
#
# Snapshot ids look like: 20260811-013542-main
# (YYYYMMDD-HHMMSS-<branch>)
#
# Snapshots live in: ${SNAPSHOT_DIR:-~/.cache/luna-edit-snapshots}
# Each snapshot is a full hard-link copy of the repo (cheap), named
# after the snapshot id.

set -euo pipefail

SNAPSHOT_DIR="${SNAPSHOT_DIR:-$HOME/.cache/luna-edit-snapshots}"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'no-branch')"

cmd="${1:-}"
shift || true

ensure_dir() {
    mkdir -p "$SNAPSHOT_DIR"
}

# ── save ────────────────────────────────────────────────────────────
do_save() {
    local label="${1:-}"
    ensure_dir
    local ts
    ts="$(date -u +%Y%m%d-%H%M%S)"
    local id="${ts}-${BRANCH}"
    [[ -n "$label" ]] && id="${id}-${label}"
    local dest="$SNAPSHOT_DIR/$id"

    if [[ -e "$dest" ]]; then
        echo "edit-snapshot: $id already exists (collision); aborting" >&2
        exit 1
    fi

    # Copy the repo into the snapshot directory. We use `cp -a` (archive)
    # so the snapshot is INDEPENDENT of subsequent changes to the source —
    # a hard-link approach (`cp -al`) breaks because hard-links share
    # inodes and any modification to the source mutates the snapshot too.
    #
    # For a typical flake (150 files, ~3MB) this is essentially instant.
    # For larger repos, we'd want to switch to a git-stash-based approach
    # or a real COW filesystem (btrfs subvolume snapshot). The current
    # repo is small enough that cp -a is fine.
    #
    # .git is excluded (we don't snapshot git's internal state — git
    # itself is the source of truth for git state).
    cp -a "$REPO_ROOT/." "$dest/" 2>/dev/null || {
        echo "edit-snapshot: cp -a failed; aborting" >&2
        rm -rf "$dest"
        exit 1
    }

    # Remove .git from the snapshot — we don't want to mutate git
    # state by reverting.
    rm -rf "$dest/.git"

    # Write metadata.
    cat > "$dest/.edit-snapshot-meta" <<META
id=$id
created=$(date -u +%Y-%m-%dT%H:%M:%SZ)
repo=$REPO_ROOT
branch=$BRANCH
label=$label
META

    echo "$id"
}

# ── list ────────────────────────────────────────────────────────────
do_list() {
    ensure_dir
    local snaps
    snaps=$(find "$SNAPSHOT_DIR" -maxdepth 2 -name '.edit-snapshot-meta' 2>/dev/null | sort -r)
    if [[ -z "$snaps" ]]; then
        echo "(no snapshots)"
        return
    fi
    printf '%-30s  %-22s  %s\n' ID CREATED LABEL
    printf '%-30s  %-22s  %s\n' -- ------- -----
    while IFS= read -r meta; do
        local id created label branch
        id=$(grep '^id=' "$meta" | cut -d= -f2-)
        created=$(grep '^created=' "$meta" | cut -d= -f2-)
        label=$(grep '^label=' "$meta" | cut -d= -f2-)
        branch=$(grep '^branch=' "$meta" | cut -d= -f2-)
        printf '%-30s  %-22s  branch=%s label=%s\n' "$id" "$created" "$branch" "$label"
    done <<< "$snaps"
}

# ── last ───────────────────────────────────────────────────────────
do_last() {
    ensure_dir
    local snaps
    snaps=$(find "$SNAPSHOT_DIR" -maxdepth 2 -name '.edit-snapshot-meta' 2>/dev/null | sort -r)
    [[ -z "$snaps" ]] && { echo "(no snapshots)" >&2; exit 1; }
    local first; first=$(head -1 <<< "$snaps")
    grep '^id=' "$first" | cut -d= -f2-
}

# ── revert ─────────────────────────────────────────────────────────
do_revert() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        id=$(do_last 2>/dev/null) || { echo "edit-snapshot: no id and no snapshots" >&2; exit 1; }
    fi
    local meta="$SNAPSHOT_DIR/$id/.edit-snapshot-meta"
    if [[ ! -f "$meta" ]]; then
        echo "edit-snapshot: no such snapshot: $id" >&2
        echo "  (use 'edit-snapshot.sh list' to see available)" >&2
        exit 1
    fi

    # Safety: require the user to type YES at a tty (no silent revert).
    echo "edit-snapshot: about to revert to $id"
    echo "  this will REPLACE the current working tree with the snapshot."
    echo "  uncommitted changes will be LOST."
    if [[ -t 0 ]]; then
        read -rp "  type YES to proceed: " confirm
        if [[ "$confirm" != "YES" ]]; then
            echo "edit-snapshot: abort (you typed: '$confirm')"
            exit 1
        fi
    else
        echo "edit-snapshot: no tty, skipping (use YES on stdin to confirm)" >&2
        # In non-tty context, require YES on stdin
        read -r confirm
        [[ "$confirm" == "YES" ]] || { echo "abort"; exit 1; }
    fi

    # Move the snapshot to a temp location, then move files INTO the
    # repo. We can't just `cp -a` over the top — that would error on
    # every file that exists in both. We do:
    #   1. rm -rf $REPO_ROOT/<everything except .git>
    #   2. cp -a $SNAPSHOT_DIR/$id/<everything> $REPO_ROOT/
    #
    # The snapshot's hidden .edit-snapshot-meta is excluded from the
    # copy so we don't pollute the repo. .git is preserved (we don't
    # touch git state — git is its own source of truth).

    # First, wipe the working tree (excluding .git, the snapshot metadata
    # file, and the snapshot directory itself which is OUTSIDE the repo).
    echo "edit-snapshot: wiping current tree (excluding .git)..."
    # Use find with -mindepth 1 and -delete to remove all files except .git
    # and the metadata file (in case the snapshot script is itself being
    # snapshotted — though that would be weird).
    find "$REPO_ROOT" -mindepth 1 \
        -not -path "$REPO_ROOT/.git*" \
        -not -path "$REPO_ROOT/.edit-snapshot-meta" \
        -delete 2>/dev/null || {
        # Fallback: rm -rf on every top-level entry except .git + meta.
        echo "  find -delete failed; using rm -rf"
        shopt -s dotglob
        for entry in "$REPO_ROOT"/* "$REPO_ROOT"/.[!.]*; do
            [[ -e "$entry" ]] || continue
            case "$entry" in
                "$REPO_ROOT/.git") continue ;;
                "$REPO_ROOT/.edit-snapshot-meta") continue ;;
            esac
            rm -rf "$entry"
        done
        shopt -u dotglob
    }

    echo "edit-snapshot: restoring snapshot..."
    cp -a "$SNAPSHOT_DIR/$id/." "$REPO_ROOT/"
    # Remove the metadata from the restored repo (it shouldn't be there).
    rm -f "$REPO_ROOT/.edit-snapshot-meta"

    echo "edit-snapshot: reverted to $id"
}

# ── rm ─────────────────────────────────────────────────────────────
do_rm() {
    local id="${1:-}"
    [[ -z "$id" ]] && { echo "edit-snapshot: rm requires an id" >&2; exit 1; }
    local dest="$SNAPSHOT_DIR/$id"
    [[ -e "$dest" ]] || { echo "edit-snapshot: no such snapshot: $id" >&2; exit 1; }
    rm -rf "$dest"
    echo "edit-snapshot: removed $id"
}

# ── diff ───────────────────────────────────────────────────────────
do_diff() {
    local id="${1:-}"
    [[ -z "$id" ]] && { echo "edit-snapshot: diff requires an id" >&2; exit 1; }
    local meta="$SNAPSHOT_DIR/$id/.edit-snapshot-meta"
    [[ -f "$meta" ]] || { echo "edit-snapshot: no such snapshot: $id" >&2; exit 1; }
    local snap="$SNAPSHOT_DIR/$id"
    echo "snapshot $id vs current tree:"
    # Use diff -rq to show which files differ (and which are only-in-one).
    diff -rq --exclude='.git' --exclude='.edit-snapshot-meta' \
        "$snap" "$REPO_ROOT" 2>&1 | head -100 || true
}

# ── dispatch ───────────────────────────────────────────────────────
case "$cmd" in
    save)   do_save "${1:-}" ;;
    list)   do_list ;;
    last)   do_last ;;
    revert) do_revert "${1:-}" ;;
    rm)     do_rm "${1:-}" ;;
    diff)   do_diff "${1:-}" ;;
    -h|--help|"")
        sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
        ;;
    *)
        echo "edit-snapshot: unknown command: $cmd" >&2
        exit 2
        ;;
esac
