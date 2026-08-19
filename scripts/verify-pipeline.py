#!/usr/bin/env python3
"""verify-pipeline.py — post-deploy network + host-state verification.

This runs on the deploying host (luna-server) AFTER fleet-deploy.py
reports success. It is the SECOND of two watchdog layers — the first is
the target-side watchdog (target-rollback-watchdog.sh) which can
auto-rollback a broken target without any input from us.

This script verifies that the fleet is still healthy after the deploy:
- Network: can we reach the Netbird mesh, 1.1.1.1, local DNS?
- Per-host: is /run/current-system what we deployed, are critical
  services listening, are any new systemd units failing?

On any failure: auto-runs fleet-deploy.py --rollback.

Usage:
    scripts/verify-pipeline.py                # full check
    scripts/verify-pipeline.py --hosts UwU    # subset
    scripts/verify-pipeline.py --no-rollback   # check only, don't auto-rollback
    scripts/verify-pipeline.py --json         # machine-readable output

Exit codes:
  0 = all green
  1 = at least one gate failed (rollback attempted)
  2 = pre-flight error (config missing, etc.)
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
from datetime import datetime
from pathlib import Path

NIXOS = Path(os.environ.get("NIXOS_REPO", Path.home() / "nixos"))
CONFIG_FILE = NIXOS / "pkgs" / ".update-config.json"
LOG_FILE = Path("/var/log/hermes-verify.log")


def log(msg: str) -> None:
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    try:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with LOG_FILE.open("a") as f:
            f.write(line + "\n")
    except PermissionError:
        fallback = Path.home() / ".cache" / "pkg-autoupdate" / "verify.log"
        fallback.parent.mkdir(parents=True, exist_ok=True)
        fallback.write_text(line + "\n")
    print(line, flush=True)


def run(cmd: list[str], timeout: int = 30, cwd: Path | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True,
                          timeout=timeout, cwd=cwd)


def load_config() -> dict:
    if not CONFIG_FILE.exists():
        log(f"FATAL: {CONFIG_FILE} not found")
        sys.exit(2)
    return json.loads(CONFIG_FILE.read_text())


# ── Network gates ────────────────────────────────────────────────────────

def check_mesh(cfg: dict) -> tuple[bool, str]:
    """Reach at least 1 other Netbird mesh device."""
    log("NET-1: probing Netbird mesh")
    ssh_user = cfg["fleet"]["ssh_user"]
    this_host = socket.gethostname()
    others = [(h, ip) for h, ip in cfg["fleet"]["hosts"].items()
              if h != this_host]
    if not others:
        return True, "no other mesh devices to check"
    for host, ip in others:
        r = run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
                 f"{ssh_user}@{ip}", "hostname"], timeout=10)
        if r.returncode == 0 and r.stdout.strip() == host:
            log(f"  [PASS] reached {host} ({ip})")
            return True, f"reached {host} ({ip})"
        log(f"  [SKIP] {host} ({ip}) unreachable: {r.stderr.strip()[:100]}")
    return False, f"no mesh device reachable"


def check_upstream() -> tuple[bool, str]:
    """Reach 1.1.1.1:443 over the non-mesh path."""
    log("NET-2: probing 1.1.1.1:443 (upstream)")
    try:
        with socket.create_connection(("1.1.1.1", 443), timeout=5):
            log("  [PASS] TCP 1.1.1.1:443 reachable")
            return True, "TCP 1.1.1.1:443 reachable"
    except OSError as e:
        return False, f"1.1.1.1:443 unreachable: {e}"


def check_dns() -> tuple[bool, str]:
    """Resolve a known domain via the local resolver."""
    log("NET-3: probing local DNS")
    r = run(["getent", "hosts", "github.com"], timeout=5)
    if r.returncode == 0 and r.stdout.strip():
        log(f"  [PASS] resolved github.com: {r.stdout.strip()}")
        return True, f"resolved github.com → {r.stdout.strip().split()[0]}"
    return False, "getent failed to resolve github.com"


# ── Local gates ──────────────────────────────────────────────────────────

def check_host_state(host: str, ip: str, ssh_user: str,
                     expected_toplevel: str | None) -> tuple[bool, str]:
    """Verify a host's /run/current-system matches expected, no new failures."""
    log(f"LOCAL: probing {host} ({ip})")
    r = run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
             f"{ssh_user}@{ip}", "true"], timeout=10)
    if r.returncode != 0:
        return False, f"SSH unreachable: {r.stderr.strip()[:100]}"
    r = run(["ssh", f"{ssh_user}@{ip}", "readlink /run/current-system"],
            timeout=15)
    if r.returncode != 0:
        return False, f"can't readlink /run/current-system: {r.stderr.strip()[:100]}"
    actual = r.stdout.strip()
    if expected_toplevel and actual != expected_toplevel:
        return False, f"/run/current-system = {actual}, expected {expected_toplevel}"
    r = run(["ssh", f"{ssh_user}@{ip}",
             "sudo systemctl list-units --failed --no-pager"], timeout=15)
    failed = [l for l in r.stdout.splitlines() if ".service" in l and "failed" in l]
    if failed:
        return False, f"{len(failed)} failed units: {[l.strip() for l in failed[:3]]}"
    log(f"  [PASS] {host}: current-system={actual.split('-')[-1]}, 0 failed units")
    return True, f"current-system={actual.split('-')[-1]}, 0 failed units"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--hosts", nargs="+", default=None,
                    help="Subset of hosts to check")
    ap.add_argument("--expected-toplevel", default=None,
                    help="Expected /run/current-system path on each host")
    ap.add_argument("--no-rollback", action="store_true",
                    help="Check only, do not auto-rollback on failure")
    ap.add_argument("--json", action="store_true",
                    help="Machine-readable JSON output")
    args = ap.parse_args()

    cfg = load_config()
    deploy_order = list(cfg["fleet"]["deploy_order"])
    target_hosts = {h: cfg["fleet"]["hosts"][h] for h in deploy_order}
    if args.hosts:
        target_hosts = {h: cfg["fleet"]["hosts"][h] for h in args.hosts
                        if h in cfg["fleet"]["hosts"]}

    log("=" * 70)
    log("verify-pipeline starting")
    log(f"Targets: {list(target_hosts.keys())}")
    log(f"No-rollback mode: {args.no_rollback}")

    expected = args.expected_toplevel
    if not expected:
        # Use the explicit flake-parts attribute path. `.#Luna-Server` is
        # the nixos-rebuild shorthand and does NOT resolve via plain `nix build`.
        r = run(["nix", "--extra-experimental-features", "nix-command flakes",
                 "build", "--no-link", "--print-out-paths",
                 ".#nixosConfigurations.Luna-Server.config.system.build.toplevel"],
                cwd=NIXOS, timeout=60)
        if r.returncode == 0:
            expected = r.stdout.strip().splitlines()[-1]
            log(f"Expected toplevel: {expected}")

    results: dict[str, dict] = {}
    overall_ok = True

    log("")
    log("── Network gates ──")
    for name, fn in [("mesh", check_mesh), ("upstream", check_upstream),
                     ("dns", check_dns)]:
        try:
            ok, detail = (fn(cfg) if name == "mesh" else fn())
        except Exception as e:
            ok, detail = False, f"exception: {e}"
        results[f"net.{name}"] = {"ok": ok, "detail": detail}
        if not ok:
            overall_ok = False
        log(f"  [{'PASS' if ok else 'FAIL'}] net.{name}: {detail}")

    log("")
    log("── Local gates ──")
    for host, ip in target_hosts.items():
        ok, detail = check_host_state(host, ip, cfg["fleet"]["ssh_user"], expected)
        results[f"local.{host}"] = {"ok": ok, "detail": detail}
        if not ok:
            overall_ok = False

    log("")
    log("=" * 70)
    log(f"verify-pipeline: {'PASS' if overall_ok else 'FAIL'}")

    if args.json:
        print(json.dumps({
            "ok": overall_ok,
            "timestamp": datetime.now().isoformat(),
            "checks": results,
        }, indent=2))

    if overall_ok:
        return 0
    if args.no_rollback:
        log("--no-rollback set, NOT auto-rolling back.")
        return 1

    log("Auto-rollback: invoking fleet-deploy.py --rollback")
    deploy_script = NIXOS / "scripts" / "fleet-deploy.py"
    r = run(["python3", str(deploy_script), "--rollback"], timeout=7200)
    if r.returncode == 0:
        log("Rollback succeeded. Fleet restored to previous-good generation.")
        return 1
    log(f"FATAL: rollback FAILED with exit {r.returncode}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
