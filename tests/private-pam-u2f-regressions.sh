#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture="$ROOT/tests/fixtures/nixos-secrets"

for host in UwU UwU-Server; do
  enabled=$(nix eval --json ".#nixosConfigurations.$host.config.security.pam.services" \
    --override-input nixos-secrets "path:$fixture" \
    --apply 'services: builtins.filter (name: services.${name}.u2f.enable) (builtins.attrNames services)')
  [[ "$enabled" == '["greetd","login"]' ]] \
    || { printf 'FAIL: %s has U2F enabled outside greetd/login: %s\n' "$host" "$enabled" >&2; exit 1; }
done

printf 'private PAM U2F scope regressions: PASS\n'
