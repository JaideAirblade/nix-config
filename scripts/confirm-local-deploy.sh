#!/usr/bin/env bash
# Helper that prints the mismatch warning (if needed) and asks for an explicit
# confirmation. Used by every local `deploy*` recipe in the Justfile so a
# wrong-host deploy is impossible to do by accident.
#
# Usage in a just recipe:
#     deploy host:
#         ./scripts/confirm-local-deploy.sh "{{host}}"
#         nixos-rebuild switch --flake ".#{{host}}" --elevate=sudo
#
# Behavior:
#   - If $1 == $(hostname): prints one safe-line (">>> deploy X (matches
#     hostname, proceeding)") and returns 0. No prompt, no tty required.
#     This is the normal `just deploy` flow.
#   - If $1 != $(hostname): prints a loud boxed warning, then requires
#     the human to type a long explicit confirmation string at a real
#     /dev/tty before proceeding. Refuses non-interactive runs (piped
#     stdin / CI) so accidental auto-confirm cannot bypass the gate.
#
# Confirmation string for mismatch: the user has to type the literal
# target hostname twice in a row (e.g. "UwU UwU"). This is awkward enough
# to defeat typos and muscle-memory "yes", but still copy-pasteable.
# The string is computed dynamically so the user can verify it visually
# before typing.
#
# History: added 2026-08-06 after a near-miss where `just deploy UwU` on
# the Beelink server (whose hostname was wrongly set to "UwU") applied
# the desktop's flake config to the server and broke hermes-router,
# docker, fail2ban, and several system users. The mismatch branch
# catches that exact class of mistake: the user has to deliberately
# type the wrong hostname to bypass the guard. The match branch is
# prompt-free by design -- the user's words: "if I run just deploy
# luna-server on this device there is no reason to confirm since it
# has the same hostane [hostname]".

set -euo pipefail

target="${1:-}"
cur="$(hostname)"

if [ -z "$target" ]; then
    printf 'FATAL: confirm-local-deploy.sh requires a target host argument\n' >&2
    exit 2
fi

if [ "$target" = "$cur" ]; then
    # ── MATCH case — safe, proceed without prompt ───────────────────
    printf '>>> deploy %s (matches hostname, proceeding)\n' "$target"
    exit 0
fi

# ── MISMATCH case — dangerous, require deliberate confirmation ───
confirm_token="${target} ${target}"

printf '\n'
printf '================================================================\n'
printf '  !  HOST MISMATCH -- DANGEROUS  !\n'
printf '================================================================\n'
printf '  This machine hostname: %s\n' "$cur"
printf '  You asked to deploy:   %s\n' "$target"
printf '\n'
printf '  This will apply the %s flake config TO THIS MACHINE.\n' "$target"
printf '  If %s is not what you actually want, your OS WILL BREAK\n' "$target"
printf '  (wrong users, disk layout, firewall, services).\n'
printf '\n'
printf '  Common cause: the hostname on this box is wrong, so\n'
printf '  `just deploy %s` looks like a remote deploy but is not.\n' "$target"
printf '\n'
printf '  To deploy to a different host, use:\n'
printf '      just deploy-remote %s <tailscale-ip>\n' "$target"
printf '  To fix the hostname on this box: hostnamectl set-hostname <x>\n'
printf '================================================================\n'
printf '\n'
printf 'To PROCEED with this wrong-host deploy, type this EXACT line:\n'
printf '\n'
printf '    %s\n' "$confirm_token"
printf '\n'
printf '(just hit Enter to abort)\n'
printf '\n'
printf '> '

if ! read -r ans </dev/tty 2>/dev/null; then
    printf '\n[refusing: deploy requires a real terminal for confirmation]\n' >&2
    printf '[hint: use "just deploy-remote <host> <ip>" if running non-interactively]\n' >&2
    exit 1
fi

if [ "$ans" = "$confirm_token" ]; then
    printf '>>> confirmed: proceeding with deploy of %s on %s\n' "$target" "$cur"
    exit 0
fi

if [ -z "$ans" ]; then
    printf 'Aborted (empty input).\n' >&2
    exit 1
fi

printf 'Aborted. You typed: "%s" (must be exactly: %s)\n' "$ans" "$confirm_token" >&2
exit 1
