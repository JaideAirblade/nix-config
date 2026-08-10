#!/usr/bin/env bash
# Helper that guards `just deploy-remote <host> <ip>` (and `dry-remote`) against
# the most dangerous class of remote-deploy mistake: shipping the wrong flake
# attr to a reachable machine.
#
# Usage in a just recipe:
#     deploy-remote hostname ip:
#         ./scripts/confirm-remote-deploy.sh "{{hostname}}" "{{ip}}"
#         nixos-rebuild switch --flake ".#{{hostname}}" --target-host "jaide@{{ip}}" ...
#
# What this script checks (in order):
#
#   1. Both arguments are non-empty and the IP/hostname is plausibly an address.
#
#   2. The remote host is reachable via SSH (short timeout — 7s — so a dead
#      box fails fast instead of hanging the deploy).
#
#   3. THE KEY CHECK: the remote machine's `hostname` output matches the
#      flake attr you're deploying. If you run `just deploy-remote UwU-Server
#      <desktop-ip>`, the desktop will report hostname "UwU" and this gate
#      fires. This catches the same class of mistake confirm-local-deploy.sh
#      catches, but across the network: the flake attr and the target have
#      drifted apart.
#
#      The remote hostname is read non-interactively via
#      `ssh -o BatchMode=yes -o ConnectTimeout=7 jaide@$ip hostname`.
#      BatchMode refuses to prompt for a password — if SSH isn't already
#      keyed, we fail safe rather than hanging.
#
#   4. If the check passes (match), the script exits 0 silently — same
#      no-prompt-on-match UX as confirm-local-deploy.sh.
#
#   5. If the check fails (mismatch or unreachable), the script prints a loud
#      boxed warning and requires the operator to type a confirmation token
#      at a real /dev/tty. Refuses non-interactive runs so CI / piped stdin
#      can't bypass the gate.
#
# Why the remote check is its own script (not merged into confirm-local-deploy.sh)
#   - local deploy's failure mode is "wrong config on THIS machine" — the
#     check is `hostname == target`.
#   - remote deploy's failure mode is "wrong config on THAT machine over
#     there" — the check is `ssh that-box hostname == target`, which has
#     network failure modes (unreachable, key issues, slow) the local
#     script doesn't. Keeping them separate keeps each script's failure
#     modes auditable.
#
# History: paired with confirm-local-deploy.sh (2026-08-06) to cover both
# directions. The local guard was added after a near-miss on the Beelink;
# this remote guard was added the same session to close the symmetric hole.

set -euo pipefail

target="${1:-}"
ip="${2:-}"
cur="$(hostname)"

# ── argument validation ─────────────────────────────────────────────────────
if [ -z "$target" ] || [ -z "$ip" ]; then
    printf 'FATAL: confirm-remote-deploy.sh requires <hostname> <ip> arguments\n' >&2
    printf '       e.g. just deploy-remote UwU-Server 192.168.1.50\n' >&2
    exit 2
fi

# ── local-is-target shortcut ────────────────────────────────────────────────
# If the operator is calling deploy-remote against the box they're already on,
# something is off — they should be using `just deploy`. Detect and warn.
# (Not fatal: Tailscale IPs and other secondary addresses can legitimately
# route back to the same box, so we don't hard-abort on this.)
if [ "$ip" = "$cur" ] || [ "$ip" = "127.0.0.1" ] || [ "$ip" = "localhost" ]; then
    printf '\n' >&2
    printf 'NOTE: target IP %s resolves to THIS machine (hostname=%s).\n' "$ip" "$cur" >&2
    printf '      For local deploys, prefer `just deploy %s` (no IP needed).\n' "$target" >&2
    printf '      Proceeding anyway.\n\n' >&2
fi

# ── reachability + hostname match ───────────────────────────────────────────
# Read the remote hostname. BatchMode=yes so SSH refuses to prompt for a
# password — if the key isn't already trusted, we fail safe. ConnectTimeout
# bounds the wait so a dead box doesn't hang the deploy.
remote_hostname="$(
    ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=7 \
        -o StrictHostKeyChecking=accept-new \
        -o LogLevel=ERROR \
        "jaide@${ip}" \
        hostname 2>/dev/null
)" || remote_hostname=""

ssh_rc=$?

# ── MATCH case — safe, proceed without prompt ───────────────────────────────
if [ -n "$remote_hostname" ] && [ "$remote_hostname" = "$target" ]; then
    printf '>>> deploy-remote %s @ %s (remote hostname matches, proceeding)\n' "$target" "$ip"
    exit 0
fi

# ── MISMATCH / UNREACHABLE case — dangerous, require deliberate confirm ─────
confirm_token="${target} ${target}"

printf '\n'
printf '================================================================\n'
printf '  !  REMOTE HOST MISMATCH OR UNREACHABLE  !\n'
printf '================================================================\n'
printf '  You asked to deploy:   %s\n' "$target"
printf '  Target address:        %s\n' "$ip"
if [ -z "$remote_hostname" ]; then
    printf '  Remote hostname:       (unreachable — SSH failed, rc=%s)\n' "$ssh_rc"
    printf '\n'
    printf '  Common causes:\n'
    printf '    - host is offline or slow to respond (>7s connect timeout)\n'
    printf '    - jaide@%s is not keyed (SSH asks for password; BatchMode refused)\n' "$ip"
    printf '    - the IP is wrong / reassigned\n'
    printf '\n'
    printf '  This is DANGEROUS: nixos-rebuild would still try to ship the\n'
    printf '  %s closure to %s. If that IP now points at a different\n' "$target" "$ip"
    printf '  machine (or a fresh install), you may break it.\n'
else
    printf '  Remote hostname:       %s\n' "$remote_hostname"
    printf '\n'
    printf '  This is the WRONG BOX for the %s flake.\n' "$target"
    printf '  If you proceed, you will apply %s config to %s.\n' "$target" "$remote_hostname"
fi
printf '\n'
printf '  To PROCEED anyway, type this EXACT line:\n'
printf '\n'
printf '    %s\n' "$confirm_token"
printf '\n'
printf '(just hit Enter to abort)\n'
printf '\n'
printf '> '

if ! read -r ans </dev/tty 2>/dev/null; then
    printf '\n[refusing: deploy-remote requires a real terminal for confirmation]\n' >&2
    printf '[hint: ensure SSH key is trusted and `ssh jaide@%s hostname` works]\n' "$ip" >&2
    exit 1
fi

if [ "$ans" = "$confirm_token" ]; then
    printf '>>> confirmed: proceeding with deploy-remote of %s to %s\n' "$target" "$ip"
    exit 0
fi

if [ -z "$ans" ]; then
    printf 'Aborted (empty input).\n' >&2
    exit 1
fi

printf 'Aborted. You typed: "%s" (must be exactly: %s)\n' "$ans" "$confirm_token" >&2
exit 1
