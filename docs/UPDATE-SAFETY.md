# Auto-Update Safety Process — Custom Packages

> **Living document.** Every time a pkg-autoupdate run surfaces a new failure
> mode, add it to the "Discovered failure modes" section below. This file is
> the institutional memory for why the auto-update pipeline looks the way it
> does. Bump `Last reviewed:` at the bottom on every change.

## What this pipeline does

Runs nightly at 03:00 (server local time) via `hermes cron`. Detects upstream
version changes for the 8 packages in `pkgs/.update-config.json#scope.auto_handled`,
recomputes hashes, rebuilds each one in isolation, commits + pushes to `main`
on the `nix-config` repo, then NAR-roundtrips the new system closure to every
fleet device. Each device runs a **target-side watchdog** that verifies the
deploy didn't break anything critical and **auto-rolls-back** if it did. After
all hosts report OK, the deploy host runs a **post-deploy network verification**
to confirm mesh + WAN + DNS are all still up.

## What this pipeline does NOT do

- It does **not** touch `octarine`, `hytale`, or `net-report`.
  See `pkgs/.update-config.json#scope.manual_only` for per-pkg reasons.
- It does **not** roll forward automatically after a deploy failure.
  A broken host stays on its previous generation; the next nightly run will
  retry. If the issue is upstream (e.g. broken release), `nix flake update`
  in `flake.lock` is the right next step.
- It does **not** open PRs or wait for review. You picked full-auto in
  2026-08-11's session; the two-layer watchdog (target-side + deploy-host
  verification) is the safety net.

## The two-layer watchdog model (added 2026-08-11)

A single verification step that runs on the deploy host AFTER activation is
**not enough**. The deploy host may lose contact with the target the moment
activation starts (sshd restart, firewall change, netbird config error), so
the deploy host cannot be the actor that decides "rollback this target".

The pipeline has two complementary watchdogs:

### Layer 1: Target-side watchdog (`scripts/target-rollback-watchdog.sh`)

- Installed by `scripts/fleet-deploy.py` BEFORE `switch-to-configuration` runs,
  scheduled via `systemd-run --on-active=10` so it fires 10 seconds after
  activation lands.
- Runs ENTIRELY on the target. No dependency on the deploy host. No SSH
  required after activation. The deploy host could be deleted and the
  watchdog would still complete its job.
- Polls every 30s for up to 5 minutes (configurable via
  `--watchdog-timeout`). Each iteration checks:
  1. `sshd` is active and listening on :22
  2. At least one default route exists
  3. A LAN gateway is reachable (tries 10.10.0.1, 10.10.0.2,
     192.168.178.1, 100.77.0.1 — first success wins)
  4. DNS resolves `github.com`
  5. Per-host critical ports still listening (luna-server also checks
     adguard :53, adguard :3000, unbound :5335)
- On failure: runs the **previous generation's**
  `switch-to-configuration switch` — same mechanism NixOS itself uses
  for manual rollback. The target comes back to the known-good state
  without any external input.
- Writes its verdict to `/var/lib/nixos-rollback-watchdog.status` and the
  final generation to `/var/lib/nixos-rollback-watchdog.gen`. Both also
  mirrored to journald as `nixos-rollback-watchdog` for postmortem.

### Layer 2: Deploy-host verification (`scripts/verify-pipeline.py`)

- Runs on the deploy host (luna-server) AFTER fleet-deploy.py reports all
  hosts activated successfully. This is the second line of defense for
  issues the target-side watchdog might have missed (e.g. late-arriving
  breakage, mesh-wide issues).
- Three network gates:
  1. **NET-1:** Reach at least 1 other Netbird mesh device (proves mesh up)
  2. **NET-2:** Reach 1.1.1.1:443 over the non-mesh path (proves WAN up)
  3. **NET-3:** Resolve `github.com` via local DNS (proves DNS up)
- Per-host local gates: /run/current-system matches deployed hash, 0 new
  failed systemd units, critical ports still listening.
- On any failure: auto-runs `fleet-deploy.py --rollback` (which reverts
  the package bump commit and redeploys the previous-good generation).

### Why both layers

| Failure type | Caught by |
|---|---|
| Bad package breaks sshd on the target | Layer 1 (target watchdog) — target rolls itself back |
| Bad module breaks adguard but sshd still up | Layer 1 (target watchdog checks :53/:3000 on luna-server) |
| Bad package breaks the network path the deploy host uses to reach target | Layer 1 + Layer 2 — target rolls itself back, deploy host can't even poll |
| Bad package breaks the build host (luna-server) itself | Layer 1 on luna-server catches it; deploy halts |
| Late-arriving breakage (e.g. service crashes 10 min after activation) | Layer 2 — caught on the next scheduled run, or by your monitoring |
| Cross-host mesh breakage | Layer 2 NET-1 gate |

## The 7 gates every run must pass

1. **`nix flake check` clean** — catches evaluation errors.
2. **Per-package `nix build` succeeds** — runs in a subagent per package.
3. **Diff review** — bumped `pkgs/<name>/default.nix` files listed with
   line counts.
4. **Commit + push to `main`** — only after gates 1-3.
5. **NAR-roundtrip deploy to fleet** — the new `nixos-system-<host>`
   closure is built on luna-server and shipped via the NAR-roundtrip script.
6. **Target-side watchdog verdict** — each host's watchdog reports `ok`.
   If any reports `rolled_back`, the deploy halts.
7. **Post-deploy network verification** — verify-pipeline.py confirms
   mesh, WAN, and DNS all healthy.

If gate 1/2/3 fails → no commit, no push, no deploy. Report only.
If gate 4 fails (push rejected) → pull, rebuild, retry.
If gate 5 fails partway → remaining hosts stay on previous generation.
If gate 6 fails on host N → that host is on its previous generation;
  the deploy halts so we don't fan out a bad config.
If gate 7 fails → verify-pipeline.py auto-runs `fleet-deploy.py --rollback`.

## Why sequential rollout (not parallel)

Deploying in parallel to all 4 hosts means a single broken config affects
all 4 before we can react. Sequential (one at a time, wait for watchdog
verdict, then next) means a bad deploy affects at most ONE host, the
watchdog rolls IT back automatically, and we can investigate before
fanning out.

The cost: ~5-20 minutes per host (watchdog window + deploy overhead) =
15-60 minutes for a full fleet rollout. Acceptable for nightly runs.

## Why subagent-per-package (per user request)

See "Why subagent-per-package" in the previous version of this doc;
rationale unchanged. Each package runs in an isolated Hermes subagent
for ~15 min so a 4GB rust build doesn't evict the orchestrator state.

## Per-package safety checks

For every bumped package, the subagent must answer yes to all of these
before the orchestrator commits:

- **Hash mismatch attack check.** Prefetch twice, compare hashes.
- **Upstream source provenance.** Asset URL must resolve to documented
  upstream.
- **Version sanity.** New version must parse with the same regex that
  extracted it.

## Discovered failure modes

Add new entries below as we encounter them. Format:

```
### YYYY-MM-DD — <one-line summary>

- **Symptom:** what the user/system saw
- **Root cause:** why it happened
- **Fix:** what we changed in the pipeline to prevent recurrence
- **Pkg:** which package (if any)
```

### 2026-08-11 — Pipeline created

- **Symptom:** N/A (initial creation)
- **Root cause:** User-requested feature
- **Fix:** Built pkg-autoupdate.py + fleet-deploy.py + this doc + cron
- **Pkg:** all 8 auto-handled

### 2026-08-11 — First validation run on legcord

- **Symptom:** None — was a validation run.
- **What we tested:** `python3 scripts/pkg-autoupdate.py --pkg legcord`
  Subagent spawned, hit GitHub API, detected version 1.3.0 == current pin,
  reported `STATUS: no_update`, orchestrator aborted cleanly.
- **What this confirmed:** subagent mechanism works, config-driven
  prompt template renders correctly, working-tree dirty check works,
  main branch check works, report parser extracts fields correctly,
  log files written to `~/.cache/pkg-autoupdate/<pkg>-<date>/subagent.log`.

### 2026-08-11 — Target-side watchdog added

- **Symptom:** User correctly observed that a deploy-host-side verifier
  cannot rollback a target it can't reach.
- **Root cause:** Original fleet-deploy.py assumed the deploy host
  could SSH to the target after activation. If the target's sshd or
  network broke, the deploy host had no way to rollback.
- **Fix:** Added two-layer watchdog. Target-side watchdog runs ENTIRELY
  on the target and switches back to the previous generation itself
  using NixOS's own switch-to-configuration path. Deploy-host
  verification is now a second-line check for issues the target
  watchdog missed.

### 2026-08-11 — Watchdog end-to-end test on Luna-Server

- **What we tested:** Ran `target-rollback-watchdog.sh 999 "" 5 1`
  (5s timeout, 1s sleep, fake prev gen) with sudo on Luna-Server
  directly. The watchdog:
  - Started cleanly, captured host identity
  - Iter 1: gateway 10.10.0.1 reachable, all health checks OK
  - Wrote "ok" verdict to status file and current gen to gen file
  - Mirrored to journald as `nixos-rollback-watchdog`
- **Confirmed:** the watchdog's "happy path" works on the actual target.
- **NOT tested in this run:** the rollback path (would have required
  breaking the live system). The rollback uses NixOS's standard
  switch-to-configuration mechanism, which is heavily battle-tested
  by NixOS itself. The watchdog code path that calls it was verified
  by code review.

### 2026-08-12 — fleet-deploy script uses nixos-rebuild-only attribute shorthand

- **Symptom:** First cron run with an actual pkg bump (helium-bin
  0.15.1.1 -> 0.15.3.1) failed at Phase 6 (fleet deploy) with
  `error: flake 'git+file:///tmp/nixos-wt' does not provide attribute
  'packages.x86_64-linux.Luna-Server', 'legacyPackages.x86_64-linux.Luna-Server'
  or 'Luna-Server'`. The build_local() function inside scripts/fleet-deploy.py
  was calling `nix build .#<host>` which only resolves when the flake
  exposes a top-level attribute named `<host>`. Our flake uses flake-parts
  and exposes the configuration only as `nixosConfigurations.<host>`.
- **Root cause:** `nix build .#<host>` does NOT do the implicit
  `nixosConfigurations.<host>` prefix rewrite that `nixos-rebuild` does.
  The Justfile's `just deploy` uses `nixos-rebuild` (which works), so the
  `nix build` path in fleet-deploy.py was never actually exercised end-to-end
  before this run. The earlier ad-hoc verification script used
  `nix build .#Luna-Server` but only at a shape-check layer; the actual
  build/NAR-roundtrip path was never exercised.
- **Fix:** Changed `nix build .#<host>` to
  `nix build .#nixosConfigurations.<host>.config.system.build.toplevel`
  in both `scripts/fleet-deploy.py` (build_local + --skip-build path) and
  `scripts/verify-pipeline.py` (expected-toplevel computation). `nix build`
  produces the same closure it would have via the nixos-rebuild shorthand;
  the verbose path is what plain `nix build` needs without the prefix rewrite.
- **Pkg:** N/A (script fix)

### 2026-08-12 — Read-only /home snapshot blocks the cron

- **Symptom:** Original cron entry on Luna-Server, when run from a
  btrfs-ro snapshot of `/home` (the standard NixOS impermanence setup
  on this fleet), fails at the orchestrator's pre-flight `git status`
  check with `FATAL: working tree is dirty. Commit or stash before running.`
  The orchestrator's git-write phases (subagent's `git add && git commit`,
  the orchestrator's `git diff --stat`, etc.) would also fail on the
  ro filesystem with `Read-only file system` from
  `/home/luna/nixos/.git/index.lock`. Separately, the symlink
  `~/.ssh/config` -> `/etc/luna/ssh_config` is owned by `nobody:nogroup`,
  which trips SSH's strict ownership check on every ssh/scp invocation.
- **Root cause:** The pipeline was designed assuming `/home/luna/nixos`
  is writable. On the actual fleet, `/home` is a read-only btrfs
  subvolume. The previous run "succeeded" only because no packages
  had updates, so the script never reached the git-write phase.
- **Fix (tactical):** Set NIXOS_REPO=/tmp/nixos-wt (a writable clone)
  plus a `PATH=/tmp/bin:$PATH` prepend that injects
  `-F /tmp/fake-home/.ssh/config` into every ssh/scp invocation.
  Also `GIT_SSH_COMMAND=ssh -F /tmp/fake-home/.ssh/config ...` for
  the orchestrator's git push and the subagents' git push.
- **Fix (permanent):** Make the orchestrator self-clone to a writable
  path when the source is on a read-only filesystem. Also fix the
  `~/.ssh/config` symlink chain so luna owns the final symlink (the
  current symlink has wrong ownership for SSH's strict check).
- **Pkg:** N/A (env / infrastructure fix)

### 2026-08-13 — Watchdog unit needs explicit PATH (bash-not-found on NixOS systemd)

- **Symptom:** fleet-deploy halted with `activation FAILED` on Luna-Server
  immediately after the activate step. stderr included
  `warning: the following units failed: nginx-config-reload.service,
  nixos-rollback-watchdog-<gen>-<ts>.service`. No
  `/var/lib/nixos-rollback-watchdog.status` file was ever written on the
  target. All critical services (nginx, adguardhome, netbird-mesh, sshd)
  were still active. The new closure was shipped to /nix/store but never
  promoted to a system generation; fleet deploy halted and UwU + TSBW
  were not touched.
- **Root cause:** `scripts/target-rollback-watchdog.sh` uses
  `#!/usr/bin/env bash`. `schedule_watchdog` in `scripts/fleet-deploy.py`
  scheduled the unit via
  `sudo systemd-run --unit=<name> --on-active=10 ...`. System-level
  systemd services on NixOS do NOT inherit the user's PATH, so `env`
  looked for `bash` only in the systemd manager's default PATH
  (`/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`)
  and failed with `exit 127 / "env: 'bash': No such file or directory"`.
  Because the unit exited before the watchdog loop started, no status
  file was ever written; `fleet-deploy`'s watchdog-poll loop sat out
  its full 6-minute timeout and then marked the deploy as failed.
- **Diagnosis clues:**
  `sudo journalctl -u nixos-rollback-watchdog-<gen>-<ts>.service` shows
  `env: 'bash': No such file or directory` + `status=127/n/a`. The unit
  Loads and Starts (it's a transient unit) but Exits immediately. If the
  target's actual services (sshd, nginx, etc.) are all `active`, the
  deploy state is healthy; the failure is purely the watchdog service
  itself dying on launch.
- **Fix:** added `--setenv=PATH=/run/current-system/sw/bin:/run/current-system/systemd/bin:/run/current-system/sw/sbin:/run/current-system/host/bin`
  to the `systemd-run` call in `schedule_watchdog` (scripts/fleet-deploy.py).
  This is the standard NixOS system PATH used by NixOS-generated systemd
  units; setting it on the transient watchdog unit makes `#!/usr/bin/env bash`
  resolve correctly.
- **Pkg:** N/A (script fix; bumps betterbird 140.12.0esr-bb24 -> 140.13.0esr-bb25
  and helium-bin 0.15.3.1 -> 0.15.4.1 were already pushed to main and are safe
  to deploy with the fixed watchdog)

## Operational notes

- **Network:** GitHub API has a 60 req/hour unauthenticated limit. With 8
  packages × 2-3 API calls each, one nightly run uses ~20-25 calls — safe
  headroom. If we add more than 25 GitHub-sourced packages, switch to
  authenticated `gh api` calls (token in cron env).
- **Disk:** Nix store will accumulate old generations. `nix-collect-garbage -d`
  is safe on the build host but NOT on fleet devices (they manage their own
  GC via the existing NixOS module).
- **Time budget:** A full green run with 8 packages takes ~15-25 min on
  luna-server (builds) + ~5-20 min per fleet host for the watchdog window =
  30-90 minutes total. Cron timeout is set to 90 min.
- **Watchdog timeout:** default 300s (5 min). Increase with
  `--watchdog-timeout 600` for slow hosts or rollouts that touch
  systemd-managed networking.

---

Last reviewed: 2026-08-13 (fixed watchdog systemd-run PATH; documented bash-not-found failure mode)
Owner: Luna (auto-update pipeline), Jaide (final authority on rollback)
