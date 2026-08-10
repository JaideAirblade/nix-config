#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; cleanup_real_scripts' EXIT
marker="$tmp/injected"
log="$tmp/args.log"

# ── Mock the guard scripts in-place ─────────────────────────────────────────
# The Justfile calls `./scripts/confirm-{local,remote}-deploy.sh` via relative
# path, so PATH-based mocking doesn't intercept them. We back up the real
# scripts and replace them with pass-through stubs for the duration of the
# test, then restore on exit. The stubs log their args (so we can assert the
# Justfile passed them literally) and exit 0 (so the recipe proceeds to the
# mocked nixos-rebuild).
guard_scripts=(scripts/confirm-local-deploy.sh scripts/confirm-remote-deploy.sh)
cleanup_real_scripts() {
  for g in "${guard_scripts[@]}"; do
    if [ -e "$g.real" ]; then
      mv "$g.real" "$g"
      chmod +x "$g"
    fi
  done
}

for g in "${guard_scripts[@]}"; do
  cp "$g" "$g.real"
  cat > "$g" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$0 \$*" >>"\$JUST_TEST_LOG"
exit 0
MOCK
  chmod +x "$g"
done

# ── Mock the build/provision commands via PATH ──────────────────────────────
mkdir -p "$tmp/bin"
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

# ── Test 1: `just deploy <hostile>` passes the payload as one literal arg ─
payload="UwU; : > $marker; #"
just deploy "$payload" >/dev/null 2>&1
[[ ! -e "$marker" ]] || { echo "FAIL: deploy host parameter executed shell syntax" >&2; exit 1; }

grep -Fq -- ".#$payload" "$log" \
  || { echo "FAIL: deploy did not pass the hostile value as one literal argument" >&2; exit 1; }

# ── Test 2: `just deploy-remote <hostile-host> <hostile-ip>` ──────────────
# Both parameters must be passed literally — neither should be shell-interpolated.
: > "$log"

# Use a literal path (not $marker) so the inner shell can't expand a test
# variable and produce a false positive. The point of this test is to verify
# the Justfile doesn't split/interpolate the parameter, not to test shell
# variable expansion inside the recipe.
hostile_host='UwU-Server; : > '"$marker"'; #'
hostile_ip='192.168.1.50; echo PWNED > /tmp/pwned; #'

just deploy-remote "$hostile_host" "$hostile_ip" >/dev/null 2>&1
[[ ! -e "$marker" ]] || { echo "FAIL: deploy-remote hostname parameter executed shell syntax" >&2; exit 1; }

grep -Fq -- "$hostile_host" "$log" \
  || { echo "FAIL: deploy-remote did not pass the hostile hostname literally" >&2; exit 1; }
grep -Fq -- "$hostile_ip" "$log" \
  || { echo "FAIL: deploy-remote did not pass the hostile ip literally" >&2; exit 1; }

# ── Test 3: no recipe parameter is interpolated as {{var}} in shell source ─
if grep -nE '\{\{[[:space:]]*(host|hostname|ip|i|iso|name|iface)([[:space:]]|\})' Justfile; then
  echo "FAIL: a recipe parameter is still interpolated into shell source" >&2
  exit 1
fi

printf 'Justfile argument regressions: PASS\n'
