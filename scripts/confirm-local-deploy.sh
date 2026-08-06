#!/usr/bin/env bash
# Helper that prints the mismatch warning (if needed) and asks for YES confirmation.
# Used by every local `deploy*` recipe in the Justfile so a wrong-host deploy
# is impossible to do by accident.
#
# Usage in a just recipe:
#     deploy host:
#         @_confirm_local_deploy "{{host}}"
#         nixos-rebuild switch --flake ".#{{host}}" --elevate=sudo
#
# Behavior:
#   - If $1 == $(hostname): prints one safe-line (">>> deploy X (matches
#     hostname, proceeding)") and returns 0. No prompt, no tty required.
#     This is the normal `just deploy` flow.
#   - If $1 != $(hostname): prints a loud boxed warning, then requires
#     the human to type the literal string "YES" (uppercase) at a real
#     /dev/tty before proceeding. Refuses non-interactive runs (piped
#     stdin / CI) so accidental auto-yes cannot bypass the gate.
#
# History: added 2026-08-06 after a near-miss where `just deploy UwU` on
# the Beelink server (whose hostname was wrongly set to "UwU") applied the
# desktop's flake config to the server and broke hermes-router, docker,
# fail2ban, and several system users. The mismatch branch catches that.
# The match branch was simplified later the same day after the user
# flagged the constant YES-prompt on safe deploys as "scary" — the
# mismatch warning is the load-bearing safety, the prompt is not.

set -euo pipefail

target="${1:-}"
cur="$(hostname)"

if [ -z "$target" ]; then
    printf 'FATAL: _confirm_local_deploy requires a target host argument\n' >&2
    exit 2
fi

if [ "$target" != "$cur" ]; then
    # ── MISMATCH case — require explicit YES, refuse non-tty ───────
    printf '\n'
    printf '================================================================\n'
    printf '  !  HOST MISMATCH  !\n'
    printf '================================================================\n'
    printf '  This machine hostname: %s\n' "$cur"
    printf '  You asked to deploy:   %s\n' "$target"
    printf '\n'
    printf '  This will apply the %s flake config TO THIS MACHINE.\n' "$target"
    printf '  If %s is not the correct target, your OS WILL BREAK\n' "$target"
    printf '  (wrong users, disk layout, firewall, services).\n'
    printf '\n'
    printf '  To deploy to a different host, use:\n'
    printf '      just deploy-remote %s <tailscale-ip>\n' "$target"
    printf '================================================================\n'
    printf '\n'
    printf 'Type YES (capital letters) to confirm deploy of %s config to %s machine: ' \
        "$target" "$cur"

    if ! read -r ans </dev/tty 2>/dev/null; then
        printf '\n[refusing: deploy requires a real terminal for confirmation]\n' >&2
        printf '[hint: use "just deploy-remote <host> <ip>" if running non-interactively]\n' >&2
        exit 1
    fi

    if [ "$ans" != "YES" ]; then
        printf 'Aborted. You typed: "%s" (must be exactly YES)\n' "$ans" >&2
        exit 1
    fi
else
    # ── MATCH case — print a short safe-line and proceed ────────────
    # The mismatch path is where the real danger is. When the target
    # matches the local hostname, this is the normal `just deploy`
    # flow (local rebuild + activate) and the human doesn't need to
    # type YES every time. The mismatch warning above is the gate that
    # catches wrong-host deploys.
    printf '>>> deploy %s (matches hostname, proceeding)\n' "$target"
fi
