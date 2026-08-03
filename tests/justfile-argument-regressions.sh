#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
marker="$tmp/injected"
log="$tmp/args.log"

for command in nix nixos-rebuild lab-create-dc; do
  {
    printf '#!%s\n' "$(command -v bash)"
    cat <<'MOCK'
printf '%s\n' "$0 $*" >>"$JUST_TEST_LOG"
MOCK
  } >"$tmp/bin/$command"
  chmod +x "$tmp/bin/$command"
done

export PATH="$tmp/bin:$PATH"
export JUST_TEST_LOG="$log"

payload="UwU; : > $marker; #"
just deploy "$payload" >/dev/null 2>&1
[[ ! -e "$marker" ]] || { echo "FAIL: deploy host parameter executed shell syntax" >&2; exit 1; }

grep -Fq -- ".#$payload" "$log" \
  || { echo "FAIL: deploy did not pass the hostile value as one literal argument" >&2; exit 1; }

if grep -nE '\{\{[[:space:]]*(host|hostname|ip|i|iso|name|iface)([[:space:]]|\})' Justfile; then
  echo "FAIL: a recipe parameter is still interpolated into shell source" >&2
  exit 1
fi

printf 'Justfile argument regressions: PASS\n'
