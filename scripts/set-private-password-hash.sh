#!/usr/bin/env bash
set -euo pipefail

SECRETS_DIR=${SECRETS_DIR:-"$HOME/nixos-secrets"}
SECRET_RELATIVE_PATH="secrets/private/accounts.yaml"
SECRET_FILE="$SECRETS_DIR/$SECRET_RELATIVE_PATH"
SOPS_CONFIG="$SECRETS_DIR/.sops.yaml"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

prompt_password() {
  local title=$1
  if command -v zenity >/dev/null 2>&1; then
    zenity --password --title="$title"
  elif command -v nix >/dev/null 2>&1; then
    nix shell nixpkgs#zenity --command zenity --password --title="$title"
  else
    fail "zenity and nix are both unavailable; cannot prompt securely"
  fi
}

notify_error() {
  local message=$1
  if command -v zenity >/dev/null 2>&1; then
    zenity --error --text="$message" || true
  elif command -v nix >/dev/null 2>&1; then
    nix shell nixpkgs#zenity --command zenity --error --text="$message" || true
  fi
}

command -v mkpasswd >/dev/null 2>&1 || fail "mkpasswd is required"
command -v sops >/dev/null 2>&1 || fail "sops is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
[[ -f "$SOPS_CONFIG" ]] || fail "missing SOPS config: $SOPS_CONFIG"

password=$(prompt_password "Shared Jaide password for private devices") || fail "password entry cancelled"
[[ -n "$password" ]] || fail "password cannot be empty"
confirmation=$(prompt_password "Confirm shared Jaide password") || fail "password confirmation cancelled"
if [[ "$password" != "$confirmation" ]]; then
  unset password confirmation
  notify_error "The passwords did not match. Nothing was changed."
  fail "passwords did not match"
fi
unset confirmation

# mkpasswd reads the password from stdin; neither plaintext nor hash appears in
# a process argument. The plaintext exists only in this process's memory.
hash=$(printf '%s\n' "$password" | mkpasswd -m yescrypt -s)
unset password
[[ "$hash" == '$y$'* ]] || fail "mkpasswd did not return a yescrypt hash"

umask 077
mkdir -p "$(dirname "$SECRET_FILE")"

if [[ -f "$SECRET_FILE" ]]; then
  # sops expects a JSON-encoded scalar on stdin. This updates ciphertext in
  # place without exposing the hash through argv or a persistent temp file.
  printf '%s' "$hash" \
    | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' \
    | sops set --value-stdin "$SECRET_FILE" '["jaide_password_hash"]'
else
  # New-file encryption needs a document. Stage it only in tmpfs, encrypt for
  # the filename's creation rule, then install the ciphertext into Git.
  tmpdir=$(mktemp -d -p /dev/shm private-password.XXXXXX)
  trap 'rm -rf "$tmpdir"' EXIT
  printf '%s' "$hash" \
    | python3 -c 'import json, sys; print(json.dumps({"jaide_password_hash": sys.stdin.read()}))' \
    >"$tmpdir/accounts.json"
  sops --config "$SOPS_CONFIG" \
    --filename-override "$SECRET_RELATIVE_PATH" \
    --encrypt --input-type json --output-type yaml \
    "$tmpdir/accounts.json" >"$tmpdir/accounts.enc.yaml"
  install -m 0600 "$tmpdir/accounts.enc.yaml" "$SECRET_FILE"
fi
unset hash

ciphertext=$(<"$SECRET_FILE")
[[ "$ciphertext" == *'ENC['* && "$ciphertext" == *'sops:'* ]] \
  || fail "result does not look like a SOPS-encrypted document"
unset ciphertext

printf 'Encrypted shared Jaide password hash written to %s\n' "$SECRET_FILE"
