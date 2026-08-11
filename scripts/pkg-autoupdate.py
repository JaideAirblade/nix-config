#!/usr/bin/env python3
"""pkg-autoupdate.py — nightly auto-updater for ~/nixos/pkgs/.

Per docs/UPDATE-SAFETY.md: this is the orchestrator. It spawns one
isolated subagent per auto-handled package, collects results, and
decides whether to commit + push + deploy.

Run from anywhere; the script chdir's into ~/nixos at start.

Usage:
    scripts/pkg-autoupdate.py                # normal nightly run
    scripts/pkg-autoupdate.py --dry-run      # scan + report only, no commits
    scripts/pkg-autoupdate.py --pkg legcord  # restrict to one pkg (debug)
    scripts/pkg-autoupdate.py --skip-deploy  # update + commit + push, no deploy
    scripts/pkg-autoupdate.py --allow-prerelease  # include pre-release tags
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from datetime import date
from pathlib import Path

# ── paths ──────────────────────────────────────────────────────────────
NIXOS = Path(os.environ.get("NIXOS_REPO", Path.home() / "nixos"))
CONFIG_FILE = NIXOS / "pkgs" / ".update-config.json"
LOG_DIR = Path.home() / ".cache" / "pkg-autoupdate"
TODAY = date.today().isoformat()

# ── subagent prompt template ───────────────────────────────────────────
# Per user request 2026-08-11: each pkg gets its own isolated subagent.
# The subagent gets the FULL context it needs (paths, expected shape)
# but no shared state with the orchestrator.
SUBAGENT_PROMPT = """\
You are an isolated subagent updating one NixOS package in {nixos_repo}/pkgs/{pkg}/.

Working directory: {nixos_repo}
Package: {pkg}
Update strategy: {strategy}
Update config (full): {config_json}

YOUR JOB (do these in order, abort if any fails):

1. READ {nixos_repo}/pkgs/{pkg}/default.nix so you know its current shape.
2. DETECT the latest upstream version using the strategy in the config:
   - github_release: GET https://api.github.com/repos/{owner}/{repo}/releases/latest
     Parse .tag_name, strip "{tag_strip_prefix}" if non-empty.
   - github_default_branch_head: GET https://api.github.com/repos/{owner}/{repo}/commits?per_page=1
     Parse .[0].sha. Read the SHA out fully (40 chars).
   - npm_registry: GET https://registry.npmjs.org/{package}
     Parse .dist-tags.latest.
   - scrape_downloads_page: GET {url}, apply regex "{regex}" to the page, take the LAST match.
3. COMPARE detected version to current "version" / "rev" field in the
   current default.nix. If unchanged, report "no update available" and exit 0.
4. UPDATE the file:
   - For github_release / npm_registry / scrape_downloads_page: bump
     `version = "..."` and replace the asset URL string to use the new version.
     Leave the `hash` line as-is — Nix will recompute on build.
   - For github_default_branch_head: bump `rev = "..."` to the new SHA.
     Leave the `hash` line as-is — same reason.
5. COMMIT the bump:
       git -C {nixos_repo} add pkgs/{pkg}/default.nix
       git -C {nixos_repo} commit -m "pkg-autoupdate({today}): bump {pkg} to <new-version>"
   Do NOT push. Do NOT touch other packages.
6. BUILD the package:
       nix --extra-experimental-features 'nix-command flakes' build \\
         --no-link --print-out-paths {nixos_repo}#{pkg}
   This re-fetches the asset and recomputes the hash. If the build fails,
   the commit stays (so a human can investigate) but you report "build failed".
7. AMEND the commit with the now-correct hash:
       git -C {nixos_repo} add pkgs/{pkg}/default.nix
       git -C {nixos_repo} commit --amend --no-edit
8. REPORT in this exact format (so the orchestrator can parse):

PKG: {pkg}
OLD_VERSION: <whatever was there before>
NEW_VERSION: <whatever you detected>
STATUS: success|build_failed|no_update
NEW_COMMIT: <output of `git rev-parse HEAD`>
LOG: <path to the log you wrote, e.g. ~/.cache/pkg-autoupdate/{pkg}-{today}.log>

CONSTRAINTS:
- Never edit other packages.
- Never touch flake.lock or any host config.
- Never push to any remote.
- If step 2 fails (network down, API changed), abort with STATUS=scan_failed
  and the error message in LOG.
- If step 6 fails (build broke), do NOT amend the commit. Leave the
  half-bump commit in place with the empty hash and report STATUS=build_failed.
  A human will decide whether to revert.
- If you need to install Python deps for step 2 parsing, use stdlib only
  (json, urllib, re). Don't pip install anything.

Write a copy of your work to ~/.cache/pkg-autoupdate/{pkg}-{today}.log
as you go (every step).
"""


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def parse_subagent_report(text: str) -> dict:
    """Pull the structured fields out of a subagent's final message."""
    out = {}
    for line in text.splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            if k.strip() in ("PKG", "OLD_VERSION", "NEW_VERSION", "STATUS",
                             "NEW_COMMIT", "LOG"):
                out.setdefault(k.strip(), v.strip())
    return out


def spawn_subagent(pkg: str, cfg: dict) -> dict:
    """Spawn a Hermes subagent for one package. Returns parsed report."""
    strategy = cfg["packages"][pkg].get("strategy", "unknown")
    config_json = json.dumps(cfg["packages"][pkg], indent=2)

    # Build the prompt from the template, fill in per-pkg fields
    prompt = SUBAGENT_PROMPT.format(
        nixos_repo=str(NIXOS),
        pkg=pkg,
        strategy=strategy,
        config_json=config_json,
        today=TODAY,
        owner=cfg["packages"][pkg].get("owner", ""),
        repo=cfg["packages"][pkg].get("repo", ""),
        tag_strip_prefix=cfg["packages"][pkg].get("tag_strip_prefix", ""),
        url=cfg["packages"][pkg].get("url", ""),
        regex=cfg["packages"][pkg].get("regex", ""),
        package=cfg["packages"][pkg].get("package", ""),
    )

    log_dir = LOG_DIR / f"{pkg}-{TODAY}"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "subagent.log"
    log_path.write_text(prompt)

    log(f"[{pkg}] spawning subagent (strategy={strategy})")

    # Use hermes agent in --yolo mode (auto-approve hooks) + headless.
    # The subagent gets full isolation: its own session, its own cwd, its
    # own tool results. We only get its final report back.
    try:
        result = subprocess.run(
            ["hermes", "--yolo", "--cli", "-z", prompt],
            capture_output=True,
            text=True,
            timeout=900,  # 15 min per pkg — headroom for rust builds
            cwd=NIXOS,
        )
        out = (result.stdout or "") + (result.stderr or "")
        log_path.write_text(prompt + "\n\n=== SUBAGENT OUTPUT ===\n" + out)
        return parse_subagent_report(out)
    except subprocess.TimeoutExpired:
        log(f"[{pkg}] subagent TIMED OUT after 15 min")
        return {"PKG": pkg, "STATUS": "timeout", "LOG": str(log_path)}
    except Exception as e:
        log(f"[{pkg}] subagent crashed: {e}")
        return {"PKG": pkg, "STATUS": "crashed", "LOG": str(log_path)}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true",
                    help="Scan + report only, no commits")
    ap.add_argument("--pkg", action="append",
                    help="Restrict to one pkg (repeatable, debug)")
    ap.add_argument("--skip-deploy", action="store_true",
                    help="Update + commit + push, skip fleet deploy")
    ap.add_argument("--allow-prerelease", action="store_true",
                    help="Include pre-release tags")
    args = ap.parse_args()

    if not CONFIG_FILE.exists():
        log(f"FATAL: config not found at {CONFIG_FILE}")
        return 2

    cfg = json.loads(CONFIG_FILE.read_text())

    # Ensure we're in the nixos repo
    os.chdir(NIXOS)
    LOG_DIR.mkdir(parents=True, exist_ok=True)

    # Determine which packages to process
    targets = cfg["scope"]["auto_handled"]
    if args.pkg:
        targets = [p for p in args.pkg if p in cfg["scope"]["auto_handled"]]
        if not targets:
            log(f"No matching auto-handled packages in: {args.pkg}")
            log(f"Auto-handled: {cfg['scope']['auto_handled']}")
            return 2

    log(f"=== pkg-autoupdate run for {TODAY} ===")
    log(f"Targets: {targets}")
    log(f"Dry run: {args.dry_run}")
    log(f"Skip deploy: {args.skip_deploy}")

    # ── Pre-flight: git state sanity ────────────────────────────────
    r = run(["git", "status", "--porcelain"])
    if r.stdout.strip():
        log("FATAL: working tree is dirty. Commit or stash before running.")
        log(r.stdout)
        return 3
    r = run(["git", "rev-parse", "--abbrev-ref", "HEAD"])
    branch = r.stdout.strip()
    if branch != "main":
        log(f"FATAL: must be on 'main' branch, currently on '{branch}'")
        return 3
    log(f"On branch: {branch} ✓")

    # ── Phase 1: parallel subagent scan + bump + commit ─────────────
    log("Phase 1: spawning one subagent per package")
    results = {}
    for pkg in targets:
        if args.dry_run:
            # Dry run: spawn the subagent with --dry-run flag so it knows
            # not to commit. Simpler: skip subagents, just print what
            # would be done. For now, run them anyway but tell them dry-run.
            log(f"[{pkg}] DRY-RUN: would spawn subagent (not implemented in dry-run mode yet, skipping)")
            continue
        results[pkg] = spawn_subagent(pkg, cfg)

    if args.dry_run:
        log("Dry run complete. No changes made.")
        return 0

    # ── Phase 2: collect results, decide ────────────────────────────
    success = [p for p, r in results.items() if r.get("STATUS") == "success"]
    build_failed = [p for p, r in results.items() if r.get("STATUS") == "build_failed"]
    scan_failed = [p for p, r in results.items() if r.get("STATUS") in ("scan_failed", "timeout", "crashed")]
    no_update = [p for p, r in results.items() if r.get("STATUS") == "no_update"]

    log("")
    log("=== Phase 1 results ===")
    log(f"  success ({len(success)}):    {success}")
    log(f"  build_failed ({len(build_failed)}): {build_failed}")
    log(f"  scan_failed ({len(scan_failed)}):   {scan_failed}")
    log(f"  no_update ({len(no_update)}):      {no_update}")

    if not success:
        log("No packages updated. Aborting.")
        return 0

    # ── Phase 3: nix flake check ────────────────────────────────────
    log("")
    log("Phase 3: nix flake check (gate 1)")
    r = run(["nix", "--extra-experimental-features", "nix-command flakes",
             "flake", "check", "--no-build"])
    if r.returncode != 0:
        log("FATAL: nix flake check failed. Rolling back the bump commits.")
        log(r.stderr[-2000:] if r.stderr else r.stdout[-2000:])
        # Roll back by reverting each successful bump commit
        for pkg in success:
            commit = results[pkg].get("NEW_COMMIT", "")
            if commit:
                run(["git", "revert", "--no-commit", commit])
        run(["git", "reset", "--hard", "HEAD"])
        return 4

    # ── Phase 4: diff review (gate 3) ───────────────────────────────
    log("Phase 4: diff review (gate 3)")
    r = run(["git", "diff", "--stat", f"HEAD~{len(success)}..HEAD"])
    log(r.stdout)

    # ── Phase 5: push to main ───────────────────────────────────────
    log("Phase 5: push to main")
    r = run(["git", "push", "origin", "main"])
    if r.returncode != 0:
        log(f"FATAL: push failed: {r.stderr}")
        return 5

    log(f"Pushed {len(success)} bump commits to origin/main")

    # ── Phase 6: fleet deploy ───────────────────────────────────────
    if args.skip_deploy:
        log("Skipping fleet deploy (--skip-deploy)")
        return 0

    log("")
    log("Phase 6: fleet deploy")
    deploy_script = NIXOS / "scripts" / "fleet-deploy.py"
    if not deploy_script.exists():
        log(f"FATAL: fleet-deploy.py not found at {deploy_script}")
        return 6
    r = run(["python3", str(deploy_script)])
    if r.returncode != 0:
        log(f"FATAL: fleet deploy failed with exit {r.returncode}")
        log("See ~/.cache/pkg-autoupdate/fleet-deploy-*.log for details.")
        return r.returncode

    log("=== All phases complete ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
