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
#   - If $1 != $(hostname): prints a loud mismatch banner, then asks YES
#   - If $1 == $(hostname): prints "safe" line, then asks YES
#   - YES must be typed literally (uppercase). Anything else aborts.
#   - Refuses to run if stdin is not a terminal (prevents piped auto-yes).
#
# History: added 2026-08-06 after a near-miss where `just deploy UwU` on
# the Beelink server (whose hostname was wrongly set to "UwU") applied the
# desktop's flake config to the server and broke hermes-router, docker,
# fail2ban, and several system users. See Mnemosyne memory ab254215582c2259.

set -euo pipefail

target="${1:-}"
cur="$(hostname)"

if [ -z "$target" ]; then
    printf 'FATAL: _confirm_local_deploy requires a target host argument\n' >&2
    exit 2
fi

if [ "$target" != "$cur" ]; then
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
else
    printf 'About to deploy %s (matches hostname, safe).\n' "$target"
    printf 'Type YES to confirm: '
fi

# Read from /dev/tty so we get the real terminal even when just's stdin is piped.
# If /dev/tty is not available, refuse rather than risk an auto-confirm from CI.
if ! read -r ans </dev/tty 2>/dev/null; then
    printf '\n[refusing: deploy requires a real terminal for confirmation]\n' >&2
    printf '[hint: use "just deploy-remote <host> <ip>" if running non-interactively]\n' >&2
    exit 1
fi

if [ "$ans" != "YES" ]; then
    printf 'Aborted. You typed: "%s" (must be exactly YES)\n' "$ans" >&2
    exit 1
fi

echo ">>> confirmed: proceeding with deploy of $target on $cur"
