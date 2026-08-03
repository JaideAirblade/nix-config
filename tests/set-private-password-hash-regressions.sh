#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/scripts/set-private-password-hash.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "password-hash helper is missing or not executable"
text=$(<"$SCRIPT")
[[ "$text" == *'zenity --password'* ]] || fail "helper does not use a hidden graphical prompt"
[[ "$text" == *'mkpasswd -m yescrypt -s'* ]] || fail "helper does not generate a salted yescrypt hash"
[[ "$text" == *'sops set --value-stdin'* ]] || fail "updates can leak the hash through process arguments"
[[ "$text" == *'/dev/shm'* ]] || fail "plaintext staging is not confined to tmpfs"
[[ "$text" == *'secrets/private/accounts.yaml'* ]] || fail "helper targets the wrong encrypted file"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/secrets"
printf '%s\n' 'creation_rules: []' >"$work/secrets/.sops.yaml"

cat >"$work/bin/zenity" <<'STUB'
set -euo pipefail
case " $* " in
  *' --password '*) printf '%s\n' 'fixture plaintext password' ;;
  *) exit 0 ;;
esac
STUB

cat >"$work/bin/mkpasswd" <<'STUB'
set -euo pipefail
[[ "$*" == '-m yescrypt -s' ]]
IFS= read -r password
[[ "$password" == 'fixture plaintext password' ]]
printf '%s\n' '$y$fixture-hash'
STUB

cat >"$work/bin/sops" <<'STUB'
set -euo pipefail
if [[ " $* " == *' --encrypt '* ]]; then
  input=${!#}
  content=$(<"$input")
  [[ "$content" == *'$y$fixture-hash'* ]]
  [[ "$content" != *'fixture plaintext password'* ]]
  printf '%s\n' 'jaide_password_hash: ENC[fixture]'
  printf '%s\n' 'sops:' '  mac: ENC[fixture]'
  exit 0
fi
if [[ "${1-}" == set && "${2-}" == --value-stdin ]]; then
  value=$(cat)
  [[ "$value" == '"$y$fixture-hash"' ]]
  [[ "${4-}" == '["jaide_password_hash"]' ]]
  printf '%s\n' 'jaide_password_hash: ENC[updated-fixture]' >"$3"
  printf '%s\n' 'sops:' '  mac: ENC[updated-fixture]' >>"$3"
  exit 0
fi
exit 1
STUB
for stub in "$work/bin/"*; do
  content=$(<"$stub")
  printf '#!%s\n%s\n' "$(command -v bash)" "$content" >"$stub"
done
chmod +x "$work/bin/"*

PATH="$work/bin:$PATH" SECRETS_DIR="$work/secrets" bash "$SCRIPT" >"$work/output"
result="$work/secrets/secrets/private/accounts.yaml"
[[ -s "$result" ]] || fail "helper did not create encrypted accounts file"
if grep -Fq 'fixture plaintext password' "$result" "$work/output"; then
  fail "plaintext password escaped the prompt/hash pipeline"
fi

PATH="$work/bin:$PATH" SECRETS_DIR="$work/secrets" bash "$SCRIPT" >>"$work/output"
grep -Fq 'ENC[updated-fixture]' "$result" \
  || fail "helper did not update an existing encrypted accounts file"
if grep -Fq 'fixture plaintext password' "$result" "$work/output"; then
  fail "plaintext password escaped the encrypted update pipeline"
fi

echo 'private password helper regressions: PASS'
