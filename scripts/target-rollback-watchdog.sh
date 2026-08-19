#!/usr/bin/env bash
# target-rollback-watchdog.sh — runs ON the target after activation.
#
# This script is the LAST line of defense. It is installed by
# scripts/fleet-deploy.py BEFORE switch-to-configuration runs, scheduled
# via `systemd-run --on-active=10`, and runs entirely on the target with
# NO dependency on the deploy host. If the deploy host goes away (or the
# target loses network), this watchdog still runs and can still rollback.
#
# Required args:
#   $1 = previous generation number (e.g. "147"). The watchdog will
#        switch back to this generation if health checks fail.
#   $2 = deploy host SSH target (e.g. luna@100.77.228.137). Used for
#        best-effort notification only — the watchdog does NOT depend
#        on being able to reach this host.
#   $3 = timeout seconds (default 300 = 5 min). The watchdog runs health
#        checks every 30s for this duration, then exits success if all
#        checks passed.
#   $4 = sleep interval seconds (default 30). Tests pass 1.
#
# Side effects:
#   - Writes /var/lib/nixos-rollback-watchdog.status (newline-delimited log
#     of every check + final outcome: ok | rolled_back | aborted)
#   - Writes /var/lib/nixos-rollback-watchdog.gen (the generation the
#     target is on after watchdog exits — useful for the deploy host's
#     verification poll)
#   - On health failure: runs
#       /nix/var/nix/profiles/system-${PREV_GEN}-link/bin/switch-to-configuration switch
#     which is the same activation mechanism NixOS itself uses. This will
#     bring the target back to the previous-good generation.

set -u  # NOTE: deliberately NOT set -e — we want to fall through to rollback

PREV_GEN="${1:-}"
DEPLOY_HOST="${2:-}"
WATCHDOG_TIMEOUT="${3:-300}"
# 4th arg is the sleep interval between checks. Defaults to 30s for the
# production watchdog window, but tests pass a smaller value (e.g. 1s)
# so the verification script can exercise the loop without waiting 30s.
SLEEP_INTERVAL="${4:-30}"

STATUS_FILE="/var/lib/nixos-rollback-watchdog.status"
GEN_FILE="/var/lib/nixos-rollback-watchdog.gen"

mkdir -p "$(dirname "$STATUS_FILE")"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

log() {
  local line
  line="$(ts) $*"
  echo "$line" >> "$STATUS_FILE"
  # Mirror to journald so we can `journalctl -t nixos-rollback-watchdog` on
  # the target for postmortem even if STATUS_FILE is somehow lost.
  logger -t nixos-rollback-watchdog "$*" 2>/dev/null || true
}

abort() {
  log "ABORT: $1"
  echo "aborted" >> "$STATUS_FILE"
  exit 1
}

# Sanity-check args. If PREV_GEN is empty we have no rollback target;
# bail out loudly so the deploy host's poll picks up the abort signal.
if [[ -z "$PREV_GEN" ]]; then
  abort "no PREV_GEN passed; cannot determine rollback target"
fi

# Truncate the status file on each run so the deploy host's poll always
# sees a fresh log.
: > "$STATUS_FILE"
log "watchdog started: prev_gen=$PREV_GEN timeout=${WATCHDOG_TIMEOUT}s sleep=${SLEEP_INTERVAL}s deploy_host=$DEPLOY_HOST"
log "target host: $(hostname) ($(hostname -I 2>/dev/null || echo no-ip))"

check_health() {
  local failures=()

  # Check 1: sshd is active AND listening on port 22
  if ! systemctl is-active --quiet sshd.service; then
    failures+=("sshd.service not active")
  fi
  if ! ss -tln 2>/dev/null | grep -qE '(:22[[:space:]]|\*:22[[:space:]])'; then
    failures+=("nothing listening on :22")
  fi

  # Check 2: at least one default route exists (the network is configured)
  if ! ip route show default 2>/dev/null | grep -q .; then
    failures+=("no default route")
  fi

  # Check 3: gateway reachable (proves L3 connectivity to the LAN side).
  # The gateway IP differs per host class. We try multiple candidates;
  # first success wins.
  local gw_ping_ok=0
  for gw in 10.10.0.1 10.10.0.2 192.168.178.1 100.77.0.1; do
    if ping -c1 -W2 "$gw" > /dev/null 2>&1; then
      gw_ping_ok=1
      log "  gateway $gw reachable"
      break
    fi
  done
  if [[ $gw_ping_ok -eq 0 ]]; then
    failures+=("no gateway reachable (10.10.0.1/2, 192.168.178.1, 100.77.0.1 all dead)")
  fi

  # Check 4: DNS responds locally. getent is always available; a successful
  # resolve of github.com proves both DNS and network up.
  if ! getent hosts github.com > /dev/null 2>&1; then
    failures+=("DNS resolution failed for github.com")
  fi

  # Check 5: per-host critical services listening (luna-server has more)
  local host_short
  host_short="$(hostname)"
  local expected_ports
  case "$host_short" in
    Luna-Server) expected_ports=(22 53 3000 5335) ;;
    UwU|TSBW-W01800) expected_ports=(22 53) ;;
    *) expected_ports=(22) ;;
  esac
  # 2026-08-20: TSBW's dnsproxy is battery-gated (dnsproxy-battery.service
  # stops it on battery by design — see hosts/TSBW-W01800/services/
  # battery-services.nix). When she is on battery, port 53 is NOT expected
  # to listen; requiring it made the watchdog roll back healthy deploys.
  # Detection mirrors dnsproxy-battery's own script: any Mains supply online.
  if [[ "$host_short" == "TSBW-W01800" ]]; then
    local ac=0 supply
    for supply in /sys/class/power_supply/*; do
      if [ "$(cat "$supply/type" 2>/dev/null)" = "Mains" ] \
         && [ "$(cat "$supply/online" 2>/dev/null)" = "1" ]; then
        ac=1
        break
      fi
    done
    if [ "$ac" = "0" ]; then
      expected_ports=(22)
    fi
  fi
  for port in "${expected_ports[@]}"; do
    if ! ss -tulnH 2>/dev/null | awk '{print $5}' | grep -qE ":$port$"; then
      failures+=("critical port $port not listening")
    fi
  done

  if [[ ${#failures[@]} -eq 0 ]]; then
    return 0
  fi
  log "  health check failed: ${failures[*]}"
  return 1
}

ITER=0
LAST_RESULT=fail
START_TS=$(date +%s)

while :; do
  ITER=$((ITER + 1))
  ELAPSED=$(( $(date +%s) - START_TS ))
  log "iteration $ITER (${ELAPSED}s/${WATCHDOG_TIMEOUT}s)"

  if check_health; then
    LAST_RESULT=ok
    log "  health OK"
    # One OK iteration is sufficient — break and report success.
    break
  fi
  LAST_RESULT=fail

  if [[ $ELAPSED -ge $WATCHDOG_TIMEOUT ]]; then
    log "timeout reached after ${WATCHDOG_TIMEOUT}s — last check was FAIL"
    break
  fi
  sleep "$SLEEP_INTERVAL"
done

# Record which generation we're on NOW (before any rollback)
PRE_ROLLBACK_GEN=$(readlink /run/current-system 2>/dev/null || echo unknown)
log "current generation BEFORE outcome: $PRE_ROLLBACK_GEN"

if [[ "$LAST_RESULT" == "ok" ]]; then
  log "VERDICT: deploy succeeded; staying on $PRE_ROLLBACK_GEN"
  echo "$PRE_ROLLBACK_GEN" > "$GEN_FILE"
  echo "ok" >> "$STATUS_FILE"

  # Best-effort notification to deploy host
  if [[ -n "$DEPLOY_HOST" ]]; then
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$DEPLOY_HOST" \
      "echo 'VERIFY OK: $(hostname) stable on $(basename $PRE_ROLLBACK_GEN)'" \
      2>/dev/null || true
  fi
  exit 0
fi

# FAILURE path — rollback to PREV_GEN
log "VERDICT: deploy broke the target; rolling back to generation $PREV_GEN"
ROLLBACK_BIN="/nix/var/nix/profiles/system-${PREV_GEN}-link/bin/switch-to-configuration"

if [[ ! -x "$ROLLBACK_BIN" ]]; then
  abort "rollback binary not found at $ROLLBACK_BIN — manual recovery required"
fi

if "$ROLLBACK_BIN" switch; then
  POST_ROLLBACK_GEN=$(readlink /run/current-system 2>/dev/null || echo unknown)
  log "rollback completed; now on $POST_ROLLBACK_GEN"
  echo "$POST_ROLLBACK_GEN" > "$GEN_FILE"
  echo "rolled_back" >> "$STATUS_FILE"

  # Best-effort notification to deploy host
  if [[ -n "$DEPLOY_HOST" ]]; then
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$DEPLOY_HOST" \
      "echo 'ROLLBACK: $(hostname) auto-rolled-back to gen $PREV_GEN'" \
      2>/dev/null || true
  fi
  exit 2
fi

abort "rollback itself failed — manual recovery required (IPMI/serial console)"
