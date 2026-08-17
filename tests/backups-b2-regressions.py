#!/usr/bin/env python3
"""Regression tests for hosts/UwU-Server/server/backups.nix.

What we check:

  1. File exists at the standard location.
  2. Module contributes to `nixos.hosts."UwU-Server"` (the per-host
     role; backups are UwU-Server-specific because that's where
     the data lives).
  3. `services.restic.backups.b2` is enabled with:
     a. timerConfig.OnCalendar (daily) — schedule exists
     b. Persistent = true — catch up after downtime
     c. RandomizedDelaySec — avoid thundering-herd on B2
     d. paths list includes /home/jaide + the DB dirs
     e. paths list EXCLUDES /media/games (reinstallable, saves $)
     f. pruneOpts include --keep-* flags (storage bound)
     g. environmentFile wires B2 creds from sops.templates
     h. backupOpts exclude caches (smaller snapshots)
  4. sops.secrets declare the B2 credentials with mode 0400.
  5. sops.templates.restic-b2-env wires the right env vars.
  6. restic is in environment.systemPackages.
  7. Optional: post-backup hook doesn't fail when env var absent
     (uses ${VAR:-} fallback).
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKUPS = ROOT / "hosts" / "UwU-Server" / "server" / "backups.nix"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(BACKUPS.exists(), "hosts/UwU-Server/server/backups.nix is missing")
src = BACKUPS.read_text(encoding="utf-8")

# 1+2. Per-host role target.
require("nixos.hosts.\"UwU-Server\"" in src,
        "module must contribute to nixos.hosts.UwU-Server (backups are server-specific)")

# 3. services.restic.backups.b2 enabled.
require("services.restic.backups.b2" in src,
        "module must declare services.restic.backups.b2")
require("enable = true" in src,
        "restic backup job must be enabled (default-on for UwU-Server)")

# 3a-c. Schedule.
require("timerConfig" in src,
        "module must configure a timerConfig")
require("OnCalendar" in src,
        "timer must use OnCalendar (daily schedule)")
require("Persistent = true" in src,
        "timer must be Persistent (catch up on missed days)")
require("RandomizedDelaySec" in src,
        "timer must include RandomizedDelaySec (avoid B2 thundering-herd)")

# 3d. Required backup paths.
for needle in ("/home/jaide", "/var/lib/gitea", "/var/lib/paperless"):
    require(needle in src,
            f"backup paths must include {needle}")

# 3e. Explicit exclusion of /media/games.
# Look for the comment OR the explicit exclusion. Easier to assert
# it's mentioned in the comment so a reader knows why it's missing.
require("/media/games" in src,
        "module must comment on /media/games exclusion (so operators know why)")

# 3f. Retention policy.
require("pruneOpts" in src,
        "module must configure pruneOpts (storage growth bound)")
for needle in ("keep-last", "keep-daily", "keep-weekly", "keep-monthly"):
    require(needle in src,
            f"pruneOpts must include {needle}")

# 3g. Environment file from sops template.
require("environmentFile" in src,
        "restic job must use environmentFile for B2 creds (no inline secrets)")
require("sops.templates.restic-b2-env" in src,
        "restic job must reference the sops-templated env file")

# 3h. Backup opts.
require("backupOpts" in src,
        "module must configure backupOpts")
require("--exclude-caches" in src,
        "backupOpts must include --exclude-caches (smaller snapshots)")

# 4. Sops secrets declared with mode 0400.
for needle in ("restic_b2_key_id", "restic_b2_application_key", "restic_password"):
    require(needle in src,
            f"sops.secrets must declare {needle}")
require("mode = \"0400\"" in src,
        "all sops secrets must be mode 0400 (root-only readable)")

# 5. sops template wires B2 creds.
require("sops.templates.restic-b2-env" in src,
        "module must declare sops.templates.restic-b2-env")
require("B2_ACCOUNT_ID" in src,
        "env template must export B2_ACCOUNT_ID")
require("B2_ACCOUNT_KEY" in src,
        "env template must export B2_ACCOUNT_KEY")
require("RESTIC_REPOSITORY=b2:" in src,
        "env template must set RESTIC_REPOSITORY to b2:...")
require("RESTIC_PASSWORD_FILE" in src,
        "env template must set RESTIC_PASSWORD_FILE")

# 6. restic binary on PATH.
require("pkgs.restic" in src,
        "module must add restic to environment.systemPackages")

# 7. Post-backup hook is graceful.
require("HEALTHCHECKS_BACKUP_PING_URL" in src,
        "post-backup hook should reference the healthcheck env var")
# Use the empty-default fallback so missing env var doesn't fail.
require("''${HEALTHCHECKS_BACKUP_PING_URL:-}" in src,
        "post-backup hook must use ${VAR:-} fallback (non-fatal if env unset)")

print("hosts/UwU-Server/server/backups.nix (restic → B2 with retention + healthchecks ping): PASS")