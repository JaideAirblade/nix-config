#!/usr/bin/env python3
"""fleet-deploy.py — push the current ~/nixos to every fleet device.

Per docs/UPDATE-SAFETY.md gates 5+6+7: after pkg-autoupdate.py has
committed + pushed a bump to main, this script rebuilds the system
closure locally and NAR-roundtrips it to each fleet device, then
activates + verifies.

The "verify" step is NOT done by this script polling the target via SSH
after activation. That model assumes the deploy host can reach the
target AFTER the deploy — which is exactly when we may have lost
contact.

The CORRECT model (per user correction 2026-08-11):
  "remember we can set the rollback script afterwards; it needs to be
   part of the command that deploys it. That is running on the target
   that gets deployed. Assume that as soon as we send the command to
   rebuild/switch, the target goes offline and we can NOT interact
   with it until the rollback happens if something goes wrong."

So: BEFORE activation, we install a target-side watchdog via
systemd-run. The watchdog runs entirely on the target, with no
dependency on us. After activation it:
  - Watches sshd, default route, gateway, DNS, critical ports
  - If anything's broken, switches the target BACK to the previous
    generation using switch-to-configuration (the standard NixOS path)
  - Writes the outcome to /var/lib/nixos-rollback-watchdog.status

This script then polls that status file as the source of truth.

Rollout model: SEQUENTIAL with per-host gates. Deploy to host 1, wait
for its watchdog to complete, THEN move to host 2. If host 1's
watchdog reports rolled_back, halt the rollout — don't deploy to host 2.

Usage:
    scripts/fleet-deploy.py                       # normal deploy
    scripts/fleet-deploy.py --hosts UwU UwU-Server  # subset
    scripts/fleet-deploy.py --include-phone       # also push to uwu-phone
    scripts/fleet-deploy.py --rollback            # revert + redeploy prev
    scripts/fleet-deploy.py --skip-build          # use existing build
    scripts/fleet-deploy.py --skip-activate       # push but don't switch
    scripts/fleet-deploy.py --watchdog-timeout 600  # extend watchdog window
    scripts/fleet-deploy.py --dry-run             # print plan, do nothing

Pre-flight requirements:
- luna's SSH key is trusted on every target (BatchMode=yes works)
- luna has NOPASSWD sudo on every target
- /nix/store on every target is NOT a read-only bind mount
- The nar-roundtrip-deploy.py script is at
    ~/.hermes/skills/nixos-multi-host-deploy/scripts/nar-roundtrip-deploy.py
- scripts/target-rollback-watchdog.sh exists in the repo AND has been
  pushed to origin/main (otherwise the target won't have it on disk yet;
  the watchdog install step would copy an empty file).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

NIXOS = Path(os.environ.get("NIXOS_REPO", Path.home() / "nixos"))
CONFIG_FILE = NIXOS / "pkgs" / ".update-config.json"
NAR_SCRIPT = Path.home() / ".hermes/skills/nixos-multi-host-deploy/scripts/nar-roundtrip-deploy.py"
# Patched variant: streams nix copy output to a log file instead of capturing
# into Python's pipe buffer (which fills + deadlocks on multi-GB closures
# over slow relays like TSBW). Use for any NAT-relayed target.
NAR_SCRIPT_PATCHED = Path.home() / ".hermes/skills/nixos-multi-host-deploy/scripts/nar-roundtrip-patched.py"
WATCHDOG_LOCAL = NIXOS / "scripts" / "target-rollback-watchdog.sh"
WATCHDOG_REMOTE = "/home/luna/nixos/scripts/target-rollback-watchdog.sh"
LOG_DIR = Path.home() / ".cache" / "pkg-autoupdate"
TODAY = datetime.now().strftime("%Y-%m-%d")


def log(msg: str) -> None:
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def run(cmd: list[str], timeout: int = 1800) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def load_config() -> dict:
    if not CONFIG_FILE.exists():
        log(f"FATAL: {CONFIG_FILE} not found")
        sys.exit(2)
    return json.loads(CONFIG_FILE.read_text())


def ssh(host_ip: str, ssh_user_: str, remote_cmd: str,
        timeout: int = 30) -> subprocess.CompletedProcess:
    return run(["ssh", "-o", "BatchMode=yes",
                f"{ssh_user_}@{host_ip}", remote_cmd], timeout=timeout)


# ── target-side watchdog install + poll ──────────────────────────────────

def push_watchdog_to_target(ip: str, ssh_user_: str) -> bool:
    """Copy the watchdog script to the target. We push a copy (not symlink)
    because the target may not have /home/luna/nixos checked out yet at the
    time of activation."""
    r = run(["ssh", "-o", "BatchMode=yes", f"{ssh_user_}@{ip}",
             "mkdir -p /home/luna/nixos/scripts"], timeout=10)
    if r.returncode != 0:
        log(f"  ! cannot mkdir on {ip}: {r.stderr}")
        return False
    r = run(["scp", "-o", "BatchMode=yes", str(WATCHDOG_LOCAL),
             f"{ssh_user_}@{ip}:/tmp/target-rollback-watchdog.sh.tmp"], timeout=30)
    if r.returncode != 0:
        log(f"  ! scp of watchdog failed: {r.stderr}")
        return False
    r = ssh(ip, ssh_user_,
            f"sudo install -m 0755 /tmp/target-rollback-watchdog.sh.tmp "
            f"{WATCHDOG_REMOTE} && rm /tmp/target-rollback-watchdog.sh.tmp")
    if r.returncode != 0:
        log(f"  ! install of watchdog on {ip} failed: {r.stderr}")
        return False
    log(f"  ✓ watchdog pushed to {ip}:{WATCHDOG_REMOTE}")
    return True


def get_previous_generation(ip: str, ssh_user_: str) -> str | None:
    """Returns the generation number that was active BEFORE this deploy.
    The watchdog uses this as the rollback target."""
    r = ssh(ip, ssh_user_,
            "ls -1 /nix/var/nix/profiles/ | grep '^system-' | tail -2")
    if r.returncode != 0:
        return None
    lines = [l.strip() for l in r.stdout.splitlines() if l.startswith("system-")]
    if not lines:
        return None
    if len(lines) < 2:
        log(f"  ! only one generation present on {ip} — nothing to rollback to")
        return None
    prev = lines[-2]
    m = re.match(r"system-(\d+)-link", prev)
    if not m:
        return None
    return m.group(1)


def schedule_watchdog(ip: str, ssh_user_: str, prev_gen: str,
                      deploy_host_ip: str, timeout_sec: int) -> bool:
    """Use systemd-run to schedule the watchdog on the target. It fires
    after the activation finishes + a 10s grace period."""
    unit_name = f"nixos-rollback-watchdog-{prev_gen}-{int(time.time())}"
    # NixOS system services don't inherit the user's PATH. The watchdog script
    # uses #!/usr/bin/env bash, so without PATH set the unit fails with
    # exit 127 ("bash: No such file or directory") and never writes the
    # verdict file — fleet-deploy then mis-classifies the deploy as failed
    # even though the activation itself succeeded.
    # 2026-08-13 — first observed: UwU-Server watchdog died with exit 127,
    # deploy halted, no rollback needed (system was healthy).
    nixos_system_path = (
        "/run/current-system/sw/bin:"
        "/run/current-system/systemd/bin:"
        "/run/current-system/sw/sbin:"
        "/run/current-system/host/bin"
    )
    r = ssh(ip, ssh_user_,
            f"sudo systemd-run --unit={unit_name} "
            f"--on-active=10 "
            f"--setenv=PATH={nixos_system_path} "
            f"--description='NixOS post-deploy rollback watchdog (gen {prev_gen})' "
            f"{WATCHDOG_REMOTE} {prev_gen} {deploy_host_ip} {timeout_sec}",
            timeout=20)
    if r.returncode != 0:
        log(f"  ! systemd-run failed: {r.stderr}")
        return False
    log(f"  ✓ watchdog scheduled as {unit_name} (fires +10s after activation)")
    return True


def poll_watchdog(ip: str, ssh_user_: str, timeout_sec: int) -> tuple[str, str]:
    """Poll the target for the watchdog's outcome. Returns (verdict, detail)
    where verdict is one of: ok | rolled_back | aborted | timeout | unreachable.

    Polls every 15s for up to timeout_sec + 60s (allow for activation +
    watchdog grace). The status file's last non-empty line is the verdict.
    """
    deadline = time.time() + timeout_sec + 60
    last_status = ""
    while time.time() < deadline:
        r = ssh(ip, ssh_user_,
                "cat /var/lib/nixos-rollback-watchdog.status 2>/dev/null",
                timeout=10)
        if r.returncode == 0 and r.stdout.strip():
            last_status = r.stdout.strip()
            lines = [l for l in last_status.splitlines() if l.strip()]
            tail = lines[-1].strip() if lines else ""
            if tail in ("ok", "rolled_back", "aborted"):
                return tail, last_status
        time.sleep(15)
    r = ssh(ip, ssh_user_,
            "sudo systemctl status nixos-rollback-watchdog-*.service --no-pager "
            "2>&1 | tail -20",
            timeout=15)
    detail = f"watchdog did not produce verdict in {timeout_sec + 60}s"
    if r.returncode == 0:
        detail += f"\nunit status: {r.stdout}"
    return "timeout", detail


# ── build + deploy one host ──────────────────────────────────────────────

def build_local(host: str) -> str | None:
    # NOTE: `.#<host>` shorthand does NOT resolve for flake-parts configs
    # (the flake exposes `nixosConfigurations.<host>` only, not a top-level
    # `<host>`). We must use the full attribute path. nixos-rebuild does
    # the prefix rewrite internally; plain `nix build` does not.
    log(f"Building .#nixosConfigurations.{host}.config.system.build.toplevel locally")
    r = run(["nix", "--extra-experimental-features", "nix-command flakes",
             "build", "--no-link", "--print-out-paths",
             f".#nixosConfigurations.{host}.config.system.build.toplevel"],
            timeout=3600)
    if r.returncode != 0:
        log(f"FATAL: local build of .#nixosConfigurations.{host} failed")
        log(r.stderr[-2000:] if r.stderr else r.stdout[-2000:])
        return None
    out_path = r.stdout.strip().splitlines()[-1]
    log(f"Built: {out_path}")
    return out_path


def nar_roundtrip(host: str, ip: str, out_path: str, ssh_user_: str) -> bool:
    # NAR-roundtrip timeouts. NAT-relayed targets (TSBW) need the patched
    # script (streaming nix-copy output to a log file to avoid the
    # pipe-buffer hang on multi-GB closures) AND a longer copy-timeout.
    # 2026-08-13 — first observed: TSBW NAR-roundtrip stalled at ~16 min
    # even with --copy-timeout 1800; closure ~95% shipped but the upstream
    # script's subprocess.run(capture_output=True) hung on nix copy's
    # progress text filling Python's 64KB pipe buffer.
    is_nat_relayed = host == "TSBW-W01800"
    copy_timeout = 1800 if is_nat_relayed else 600
    script = NAR_SCRIPT_PATCHED if is_nat_relayed else NAR_SCRIPT
    log(f"  NAR-roundtrip closure to {host} (copy_timeout={copy_timeout}s, "
        f"script={'patched' if is_nat_relayed else 'upstream'})")
    # Patched script takes --log-file; upstream does not.
    cmd = ["python3", str(script),
           "--target-path", out_path,
           "--remote-host", ip,
           "--remote-user", ssh_user_,
           "--max-attempts", "80",
           "--copy-timeout", str(copy_timeout)]
    if is_nat_relayed:
        log_file = LOG_DIR / f"nar-{host}-{int(time.time())}.log"
        log_file.parent.mkdir(parents=True, exist_ok=True)
        cmd += ["--log-file", str(log_file)]
    r = run(cmd, timeout=7200)
    if r.returncode != 0:
        log(f"  ! NAR-roundtrip FAILED for {host}")
        log(f"    stderr: {r.stderr[-2000:] if r.stderr else r.stdout[-2000:]}")
        return False
    log(f"  OK: closure shipped to {host}")
    return True


def activate(host: str, ip: str, out_path: str, ssh_user_: str) -> bool:
    log(f"  activate switch-to-configuration on {host}")
    r = run(["ssh", "-o", "StrictHostKeyChecking=accept-new",
             f"{ssh_user_}@{ip}",
             f"sudo {out_path}/bin/switch-to-configuration switch"],
            timeout=300)
    if r.returncode != 0:
        log(f"  ! activation FAILED for {host}")
        log(f"    stderr: {r.stderr[-2000:] if r.stderr else r.stdout[-2000:]}")
        return False
    log(f"  OK: activated on {host} (target may now be offline — "
        f"watchdog is on duty)")
    return True


def deploy_one_host(host: str, ip: str, out_path: str, ssh_user_: str,
                    deploy_host_ip: str, watchdog_timeout: int,
                    skip_activate: bool) -> tuple[str, str]:
    """Full per-host deploy with target-side watchdog."""
    log("")
    log(f"╔══ Deploying to {host} ({ip}) ══╗")

    # 1. Reachability pre-flight
    r = ssh(ip, ssh_user_, "true", timeout=10)
    if r.returncode != 0:
        return "unreachable", f"SSH unreachable: {r.stderr.strip()[:200]}"

    # 2. Push watchdog script to the target BEFORE we activate
    if not push_watchdog_to_target(ip, ssh_user_):
        return "preflight_failed", "could not install watchdog on target"

    # 3. Identify the previous-good generation (rollback target)
    prev_gen = get_previous_generation(ip, ssh_user_)
    if not prev_gen:
        return "preflight_failed", "could not determine previous generation on target"

    # 4. NAR-roundtrip the closure
    if not nar_roundtrip(host, ip, out_path, ssh_user_):
        return "nar_failed", "NAR-roundtrip failed; target untouched, no rollback needed"

    if skip_activate:
        log(f"  --skip-activate: NOT switching {host}")
        return "ok", f"{host}: NAR-roundtrip complete, activation skipped"

    # 5. Schedule the watchdog to fire 10s AFTER activation
    if not schedule_watchdog(ip, ssh_user_, prev_gen, deploy_host_ip, watchdog_timeout):
        # If we can't schedule the watchdog, we MUST NOT activate —
        # that would leave us with no safety net.
        return "preflight_failed", "could not schedule watchdog; NOT activating"

    # 6. Activate. From this point on, the target may go offline.
    if not activate(host, ip, out_path, ssh_user_):
        return "activate_failed", "activation failed before new gen took effect"

    # 7. Poll the watchdog for its verdict. This is the source of truth.
    log(f"  polling watchdog on {host} (up to {watchdog_timeout + 60}s)")
    verdict, detail = poll_watchdog(ip, ssh_user_, watchdog_timeout)
    if verdict == "ok":
        log(f"  ╚══ {host} watchdog: OK (deploy healthy) ══╝")
        return "ok", detail
    if verdict == "rolled_back":
        log(f"  ╚══ {host} watchdog: ROLLED BACK to gen {prev_gen} ══╝")
        return "rolled_back", detail
    if verdict == "aborted":
        log(f"  ╚══ {host} watchdog: ABORTED ══╝")
        return "rolled_back", "watchdog aborted (no rollback target): " + detail
    log(f"  ╚══ {host} watchdog: {verdict.upper()} ══╝")
    return verdict, detail


# ── main ────────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--hosts", nargs="+", default=None,
                    help="Subset of hosts to deploy to (default: deploy_order)")
    ap.add_argument("--include-phone", action="store_true",
                    help="Also push to uwu-phone")
    ap.add_argument("--rollback", action="store_true",
                    help="Revert HEAD and deploy previous-good generation")
    ap.add_argument("--skip-build", action="store_true",
                    help="Use existing local build")
    ap.add_argument("--skip-activate", action="store_true",
                    help="Push but don't switch-to-configuration")
    ap.add_argument("--watchdog-timeout", type=int, default=300,
                    help="Seconds for the target-side watchdog to verify "
                         "health (default: 300 = 5 min)")
    ap.add_argument("--dry-run", action="store_true",
                    help="Print plan, do nothing")
    args = ap.parse_args()

    cfg = load_config()
    fleet_cfg = cfg["fleet"]
    ssh_user_ = fleet_cfg["ssh_user"]
    deploy_host_ip = fleet_cfg["hosts"].get("UwU-Server", "127.0.0.1")
    deploy_order = list(fleet_cfg["deploy_order"])
    if args.include_phone:
        deploy_order.append("uwu-phone")
    target_hosts = {h: fleet_cfg["hosts"][h] for h in deploy_order}

    if args.hosts:
        target_hosts = {h: target_hosts[h] for h in args.hosts if h in target_hosts}
        if not target_hosts:
            log(f"FATAL: none of {args.hosts} are in deploy_order+optional phone")
            return 2

    log(f"=== fleet-deploy {'(ROLLBACK) ' if args.rollback else ''}===")
    log(f"Targets (sequential): {list(target_hosts.keys())}")
    log(f"Skip build: {args.skip_build}")
    log(f"Skip activate: {args.skip_activate}")
    log(f"Watchdog timeout: {args.watchdog_timeout}s per host")
    log(f"Deploy host: {deploy_host_ip}")

    if args.dry_run:
        log("(dry-run — exiting before any change)")
        return 0

    if args.rollback:
        log("Reverting HEAD commit")
        r = run(["git", "revert", "--no-edit", "HEAD"])
        if r.returncode != 0:
            log(f"FATAL: git revert failed: {r.stderr}")
            return 3

    # Pre-flight
    log("")
    log("─── Pre-flight ───")
    preflight_ok = True
    for host, ip in target_hosts.items():
        r = ssh(ip, ssh_user_, "true", timeout=10)
        if r.returncode != 0:
            log(f"  ✗ {host} ({ip}): SSH unreachable")
            preflight_ok = False
            continue
        r = ssh(ip, ssh_user_, "sudo -n true", timeout=10)
        if r.returncode != 0:
            log(f"  ✗ {host} ({ip}): sudo NOPASSWD not configured")
            preflight_ok = False
            continue
        log(f"  ✓ {host} ({ip}) reachable, sudo ok")
    if not preflight_ok:
        log("FATAL: pre-flight failed. Aborting before any deploy.")
        return 4

    # Sequential rollout
    log("")
    log("─── Sequential rollout (target-side watchdog per host) ───")
    failures: list[tuple[str, str, str]] = []
    halted = False
    for i, host in enumerate(target_hosts.keys(), 1):
        ip = target_hosts[host]
        log("")
        log(f"─── host {i}/{len(target_hosts)}: {host} ───")

        out_path = None
        if not args.skip_build:
            out_path = build_local(host)
            if not out_path:
                failures.append((host, "local-build-failed", "build"))
                halted = True
                break
        else:
            # --skip-build: find the existing built closure for this host.
            # See build_local() for the attribute-path rationale.
            r = run(["nix", "--extra-experimental-features", "nix-command flakes",
                     "build", "--no-link", "--print-out-paths",
                     f".#nixosConfigurations.{host}.config.system.build.toplevel"],
                    timeout=60)
            if r.returncode != 0:
                failures.append((host, "no-existing-build", "build"))
                halted = True
                break
            out_path = r.stdout.strip().splitlines()[-1]

        verdict, detail = deploy_one_host(host, ip, out_path, ssh_user_,
                                          deploy_host_ip, args.watchdog_timeout,
                                          args.skip_activate)
        if verdict == "ok":
            log(f"  ✓ {host}: deploy healthy, watchdog confirmed")
            log(f"  ─── {host} done, continuing to next host ───")
        else:
            log(f"  ✗ {host}: {verdict}: {detail[:200]}")
            failures.append((host, verdict, detail))
            halted = True
            log(f"  HALTING rollout — will NOT deploy to remaining hosts")
            break

    log("")
    log("=" * 70)
    log("=== fleet-deploy summary ===")
    log("=" * 70)
    if halted:
        log(f"HALTED after {len(failures)} failure(s):")
        for host, verdict, detail in failures:
            log(f"  ✗ {host}: {verdict}")
            log(f"    detail: {detail[:300]}")
        remaining = [h for h in target_hosts if h not in [f[0] for f in failures]]
        log(f"Remaining hosts NOT deployed: {remaining}")
        log("")
        log("Recovery options:")
        log("  - The target-side watchdog has already auto-rolled-back any "
            "host that detected breakage.")
        log("  - For the deploy host to confirm: ssh luna@<host> "
            "'cat /var/lib/nixos-rollback-watchdog.status'")
        log(f"  - Re-run for remaining hosts: scripts/fleet-deploy.py "
            f"--hosts {' '.join(remaining)}")
        log("  - Rollback the whole fleet: git revert HEAD && "
            "scripts/fleet-deploy.py --rollback")
        return 5
    log(f"All {len(target_hosts)} hosts deployed and verified ✓")
    return 0


if __name__ == "__main__":
    sys.exit(main())
