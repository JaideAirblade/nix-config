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
fleet device listed in the config.

## What this pipeline does NOT do

- It does **not** touch `octarine`, `omniroute`, `hytale`, or `net-report`.
  See `pkgs/.update-config.json#scope.manual_only` for per-pkg reasons.
- It does **not** roll forward automatically after a deploy failure.
  A broken host stays on its previous generation; the next nightly run will
  retry. If the issue is upstream (e.g. broken release), `nix flake update`
  in `flake.lock` is the right next step.
- It does **not** open PRs or wait for review. You picked full-auto in
  2026-08-11's session; if a single bad release breaks 4 devices at 3am,
  the rollback procedure (below) is the only safety net.

## The 6 gates every run must pass

A run is "deployable" only when **all** of these are true:

1. **`nix flake check` clean** — evaluates the entire flake including all
   hosts and modules. Catches evaluation errors introduced by an upstream
   shape change (e.g. a renamed option in nixpkgs that a package touched).
2. **Per-package `nix build .#<pkg>` succeeds for every bumped pkg** —
   catches build-system breakage before it ships. Runs in a subagent per
   package so a 4GB rust build doesn't OOM the orchestrator.
3. **Diff review** — the bumped `pkgs/<name>/default.nix` files are listed
   in the run report with line counts. If the diff is suspiciously large
   (more than version + hash line changes), the run halts and reports.
4. **Commit + push to `main`** — only after gates 1-3 pass. Commit message
   format: `pkg-autoupdate(<date>): bump <pkg-list>`.
5. **NAR-roundtrip deploy to fleet** — the new `nixos-system-<host>` closure
   is built on `uwu-server` (the build host) and shipped to each fleet
   device via `scripts/nar-roundtrip-deploy.py` (one NAR per missing path).
6. **Post-deploy verification** — on each target, `readlink /run/current-system`
   matches the deployed hash and `systemctl list-units --failed` shows zero
   new failures.

If gate 1, 2, or 3 fails → no commit, no push, no deploy. Report only.
If gate 4 fails (push rejected because someone else pushed first) → pull,
rebuild, retry deploy.
If gate 5 fails partway → the remaining hosts stay on their previous
generation. The next nightly run picks up where this one stopped.
If gate 6 fails → see "Rollback procedure" below.

## Why "subagent per package" (added 2026-08-11 per user request)

Each package update runs in an isolated Hermes subagent. Three concrete
benefits this gives us that a monolithic script cannot:

1. **Memory isolation.** A 4GB `cargo build` for orbolay does not evict the
   state needed to evaluate `nix flake check` for the remaining 7 packages.
2. **Per-package failure containment.** If orbolay's upstream HEAD is broken,
   only the orbolay subagent fails — the other 7 packages still get bumped.
   A monolithic script would either abort the whole run or try to ship 6
   good bumps alongside 1 known-bad one.
3. **Per-package artifact trail.** Each subagent writes its own
   `~/.cache/pkg-autoupdate/<pkg>-<date>.log` so the postmortem on a bad
   deploy names exactly which package broke what.

The orchestrator (`scripts/pkg-autoupdate.py`) collects exit codes + log
paths from all subagents and decides: green-path = commit+push+deploy,
red-path = report-only.

## Why "commit before build" (not the other way around)

Per `nixos-multi-host-deploy` SKILL.md: Nix hashes the working tree, not
git state. Building before commit captures pre-commit state → deploy
succeeds silently → new file is missing from the deployed system.

This pipeline's order is:
1. Bump `version` + clear `hash` (set to empty SRI placeholder) in
   `<pkg>/default.nix`
2. `git add` + `git commit` the bumps
3. `nix build .#<pkg>` — Nix re-fetches + recomputes the hash, the build
   writes the correct hash back to disk
4. `git add` + `git commit` the hash fixup
5. `nix flake check` + `nix build .#<pkg>` (second time) — final verify
6. Push + deploy

The two-commit dance looks redundant but is the safety net for the
"build-vs-commit race condition" verified on 2026-08-10's netbird-shim
deploy. Without it, the deployed build is stale even though `which` says
the binary is there.

## Per-package safety checks (the "are they safe?" requirement)

For every bumped package, the subagent must answer yes to all of these
before the orchestrator commits:

- **Hash mismatch attack check.** `nix-prefetch-url --type sha256 <asset-url>`
  must produce a hash that is a STRICT-FILE-CONTENT hash (Nix's SRI form
  `sha256-<base64>`), not an HTML error page hash. If the asset URL 404s
  and the server returns an HTML page with a 200 status, the "hash" would
  match the HTML body — a known attack vector. Mitigation: subagent always
  prefetches twice and compares hashes; any mismatch → abort that pkg.
- **Upstream source provenance.** The asset URL must resolve to the
  package's documented upstream (GitHub releases, NPM registry, etc.).
  A redirect to a different origin → abort.
- **Version sanity.** The new version must be parseable by the same
  regex that extracted it. If the upstream suddenly switches from semver
  to calver mid-stream (nym-vpnd's case), the regex update is a code
  change, not a runtime decision — abort + report.

## Rollback procedure

If a deploy breaks a host:

```bash
# 1. Identify the bad commit
cd ~/nixos && git log --oneline -5

# 2. Revert on the build host (uwu-server)
git revert --no-commit HEAD
git commit -m "rollback: revert pkg-autoupdate(<broken-date>)"

# 3. Re-deploy the previous-good generation to every host
./scripts/fleet-deploy.py --rollback

# 4. Verify on each host
ssh luna@<host> 'readlink /run/current-system'   # should NOT match the broken hash
ssh luna@<host> 'sudo systemctl list-units --failed --no-pager'
```

The fleet-deploy script's `--rollback` mode rebuilds the previous-good
commit, NAR-roundtrips it to every device, and activates. Same path as
a normal deploy, just from a different git HEAD.

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

## Operational notes

- **Network:** GitHub API has a 60 req/hour unauthenticated limit. With 8
  packages × 2-3 API calls each, one nightly run uses ~20-25 calls — safe
  headroom. If we add more than 25 GitHub-sourced packages, switch to
  authenticated `gh api` calls (token in cron env).
- **Disk:** Nix store will accumulate old generations. `nix-collect-garbage -d`
  is safe on the build host but NOT on fleet devices (they manage their own
  GC via the existing NixOS module).
- **Time budget:** A full green run with 8 packages takes ~15-25 min on
  uwu-server (dominated by the two rust builds: orbolay + macrotool-gtk4).
  Cron timeout is set to 90 min to leave headroom.

---

Last reviewed: 2026-08-11
Owner: Luna (auto-update pipeline), Jaide (final authority on rollback)
