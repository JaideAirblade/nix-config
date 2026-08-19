# OmniRoute (diegosouzapw/OmniRoute @ 976d670, 2026-08-07) — NixOS Replacement Audit

**Scope.** Read-only audit of `/tmp/OmniRoute-inspect` (HEAD 976d670ff3a7712df0c695f13095c43eace5e29b, v3.8.50) against the existing `hermes-router.nix` target on Luna-Server (127.0.0.1:8319). Cross-referenced with `~/nixos/hosts/Luna-Server/ai/hermes-router.nix` and the prior pre-flight at `~/.hermes/skills/software-development/nix-server-extension/references/nix-server-feasibility-preflight.md`.

## 1. Upstream Nix posture (Q1)

- `flake.nix` (lines 1-34): **dev-shell only**. Exposes `devShells.default` with `pkgs.nodejs_22` and an `npm install` hook. Does NOT export `packages.<system>.default`, `nixosModules.default`, `apps.<system>.default`, or `overlays.default`.
- `flake.lock`: pins `nixpkgs` to `NixOS/nixpkgs/nixos-25.11` (rev `b77b3de8775677f84492abe84635f87b0e153f0f`, narHash pinned).
- Not in nixpkgs (the package would be `pkgs.omniroute` — absent). Closest cousin `9router` is also absent. 9router's npm-only install path is a precedent here.
- No community flakes surfaced; prior `nix-server-feasibility-preflight.md` already documented this negative result (2026-08-07).

**Implication.** Packaging is from scratch. Either:
- (a) Wrap the published npm tarball (`omniroute-3.8.50.tgz` from npmjs) into a Nix derivation that runs `node bin/omniroute.mjs serve` — requires the upstream pre-built standalone bundle (`dist/server.js`) to ship, which it does via `prepublishOnly: "npm run build:cli-api && npm run build:cli && npm run check:pack-artifact"` (`package.json:236`) — confirmed by `bin/cli/commands/serve.mjs:34-36` checking `ROOT/dist/server.js` first, falling back to `ROOT/app/server.js`.
- (b) Build from source via `npm run build` (Next 16 + Turbopack) — heavy (~9-12 min on a 32-core box per Dockerfile:91-96) and requires the build-time pinned `OMNIROUTE_BASE_PATH` (Dockerfile:98-101, `next.config.mjs:105,111`) to be set correctly OR the produced bundle serves at root path.

## 2. Runtime, dependencies, entry point

- **Engine**: Node.js. `package.json:54` declares `engines.node = ">=22.22.2 <23 || >=24.0.0 <27"`. Recommend `pkgs.nodejs_24` (matches `nixos-25.11`).
- **Stack**: Next.js 16.2.11 (`package.json:289`), React 19.2.8, Express 5.2.1, better-sqlite3 ^13.0.2 (optional dep, `package.json:328`), node-machine-id, @ngrok/ngrok.
- **Workspace**: `pnpm-workspace.yaml` declares `open-sse` (an internal `@omniroute/open-sse` package — private workspace, `open-sse/package.json:14`). The standalone build assembles `dist/server.js` via `scripts/build/build-next-isolated.mjs`; `bin/cli/commands/serve.mjs` spawns that as the child server (lines 134-160, 220-240).
- **Native bindings** (forced at build time, Dockerfile:79-86):
  - `better-sqlite3` (compiled by node-gyp inside the build phase)
  - `tls-client-node` (fetches a platform-specific `.so`/`.dylib`/`.dll` from the bogdanfinn/tls-client GitHub Releases API on every build — a **mandatory network egress at build time** that the build refuses to silently skip)
  - optional `keytar`, `onnxruntime-node` (~316 MB CUDA binary — explicitly pruned from the npm tarball by `scripts/build/pack-artifact-policy.ts:28-34`).
- **Entry point** for systemd would be:
  ```bash
  exec node bin/omniroute.mjs serve --no-open --no-tray
  ```
  with the standalone bundle at `${pkg}/dist/server.js` (or whatever `ROOT` resolves to inside the wrapped derivation).

## 3. Config, state, env, secrets

### Data directory resolution (3-layer precedence)
From `scripts/build/bootstrap-env.mjs:36-51` and `bin/cli/data-dir.mjs:25-55`:

1. `process.env.DATA_DIR` (explicit override) — recommended Nix target: `/var/lib/omniroute`
2. `process.env.XDG_CONFIG_HOME/omniroute` (Linux XDG fallback)
3. `${HOME}/.omniroute` (legacy default — what the bootstrap will pick on a vanilla run)

For NixOS declarative: pass `DATA_DIR=/var/lib/omniroute` via the systemd unit's `environment` block. `StateDirectory = "omniroute"` creates `/var/lib/omniroute` automatically.

### Auto-generated secrets (bootstrap-env.mjs:185-222)
First-boot layer (auto-generated and persisted to `${DATA_DIR}/server.env`):
- `JWT_SECRET` (64-byte hex) — required for dashboard session cookies
- `API_KEY_SECRET` (32-byte hex) — HMAC signing of API keys
- `STORAGE_ENCRYPTION_KEY` (32-byte hex) — AES-256-GCM at-rest encryption of provider credentials in SQLite. **Bootstrap refuses to overwrite** this if `storage.sqlite` already contains `enc:v1:*` ciphertext (line 196-208) — important for migration: you must seed the key BEFORE the first DB read.
- `STORAGE_ENCRYPTION_KEY_VERSION` (defaults to `v1`)

**Hard requirement for declarative deployment**: pre-generate all four via sops and inject via `sops.templates.omniroute-server-env`. The `server.env` write path is fire-and-forget — if the filesystem isn't writable, it silently logs but the server still boots (line 230-232). On a stateful Nix volume the file does persist correctly.

### Port configuration (runtime-env.mjs:107-126, .env.example:74-83)
- `PORT` (default 20128, becomes `DASHBOARD_PORT`/`API_PORT` when split-port mode off)
- `DASHBOARD_PORT` (default = `PORT`)
- `API_PORT` (default = `PORT`)
- `LIVE_WS_PORT` (default 20132, loopback-only by default — `LIVE_WS_HOST=127.0.0.1`)
- `OMNIROUTE_PORT` (resolves to `basePort`; aliases `PORT` for env-passing)
- `HOSTNAME`/`OMNIROUTE_SERVER_HOST` (default `0.0.0.0`)
- `OMNIROUTE_MEMORY_MB` (default 512; calibrated to ~35% physical RAM when unset, `runtime-env.mjs:32-37`)
- `OMNIROUTE_USE_TURBOPACK` (default 1 in dev; irrelevant in production standalone)
- `OMNIROUTE_BASE_PATH` — **build-time only**. Set via `--build-arg` in the Dockerfile pattern or via `NEXT_PUBLIC_OMNIROUTE_BASE_PATH` if rebuilding from source (next.config.mjs:105-111).

### Bind-address / firewall constraints
- `PORT=20128`, `API_PORT=20129`, `LIVE_WS_PORT=20132` by default — three ports.
- For the Luna-Server hermes-router replacement the canonical loopback-only config is `HOST=127.0.0.1` mirroring `hermes-router.nix:345`. The `LIVE_WS_HOST=127.0.0.1` default already matches.
- `allowedTCPPorts` MUST NOT include 20128, 20129, or 20132 (mirror the `tests/server-hermes-extensions-regressions.py:77` assertion that `allowedTCPPorts = [ 8319 ]` is absent for hermes-router).

## 4. Network / API compatibility with the existing 127.0.0.1:8319 router

| hermes-router (existing) | OmniRoute upstream | Match |
|---|---|---|
| `POST /v1/chat/completions` (`router.py:5773`) | `POST /api/v1/chat/completions` (`src/app/api/v1/chat/completions/route.ts:1`) | ✓ Same shape; OmniRoute rejects non-JSON Content-Type with 415 (line 86-97) |
| `POST /v1/messages` (Anthropic Messages, `router.py:5804`) | `POST /api/v1/messages` (`src/app/api/v1/messages/route.ts:1`) | ✓ Both auto-convert to internal chat pipeline |
| `POST /v1/embeddings` (`router.py:5840`) | `POST /api/v1/embeddings` (`src/app/api/v1/embeddings/route.ts:1`) | ✓ |
| `GET /v1/models` (`router.py:5429`) | `GET /api/v1/models` (`src/app/api/v1/models/route.ts:25`) | ✓ Both return OpenAI-shaped `{object: "list", data: [...]}`; OmniRoute has dedicated `HEAD /v1/models` for preflight probes (line 15-23, fixes ~6s hang per #6400) |
| `GET /v1/config/providers` (`router.py:6038`) | `/api/v1/providers/...` (multiple sub-routes) | ⚠ Different shape, OmniRoute's provider catalog is dashboard-driven, not query-on-a-single-route |
| `GET /v1/usage` (`router.py:6542`) | `/api/usage` | ⚠ Different route prefix; same conceptual data |
| `GET /metrics` (`router.py:6619`) | `/api/monitoring/*`, `/api/v1/agents/health`, `/api/health`, `/api/healthz` | ⚠ Renamed |
| `POST /v1/responses` (newer OpenAI Responses API) | `POST /api/v1/responses` (`src/app/api/v1/responses/route.ts:1`) | ✓+ Additions; OmniRoute supports it natively, hermes-router does not |
| `POST /v1/audio/speech`, `/v1/audio/transcriptions` | `/api/v1/audio/speech`, `/api/v1/audio/transcriptions` | ✓ OmniRoute has extras |
| `POST /v1/images/generations` | `/api/v1/images/generations`, `/images/edits`, `/upscale` | ✓ OmniRoute has extras |
| Admin: `/v1/config/*`, `/v1/instances/*`, `/dashboard` | Many `/api/*` routes + management proxy CRUD | ⚠ OmniRoute replaces these with `/api/v1/management/*` + dashboard. The disable-admin-surfaces patch from `hosts/Luna-Server/ai/patches/hermes-router-disable-admin-surfaces.patch` does NOT translate cleanly — OmniRoute's `LOCAL_ONLY_API_PREFIXES` (`src/server/authz/routeGuard.ts:30-58`) is the new gate**: 23 prefixes enforce loopback via peer-stamp token (not Host header, see `management.ts:28-41`) |

### Auth-model delta — **CRITICAL BREAK**

| hermes-router | OmniRoute |
|---|---|
| `PROXY_API_KEYS=key1,key2,...` env var (`router.py:944, 3598-3603`) | Bearer API keys stored in SQLite, validated via `validateApiKey` (`src/sse/services/auth.ts:2435+`, `src/shared/utils/apiAuth.ts:172-181`). Multiple keys, scopes (`manage`, `read:health`, etc.), HMAC-signed with `API_KEY_SECRET`. |
| One global env-var pool (no per-key limits except per-key rate) | Per-key rate limits, scopes, `noLog` opt-out flag, audit log table |
| The user's `ROUTER_API_KEY` sops secret maps to `PROXY_API_KEYS` literally | Need to (a) start the server, (b) hit the dashboard with `INITIAL_PASSWORD` to mint the first API key, (c) store that minted key back into sops, (d) re-inject via `sops.templates.omniroute-server-env` as `OMNIROUTE_API_KEY` for client-side callers. |

**Bottom line on auth:** no clean way to **import** the existing `ROUTER_API_KEY` into OmniRoute's key store. Two options:
1. **Seed via DB**: stop the server, write a row into `${DATA_DIR}/storage.sqlite` `api_keys` table with the user's existing key hashed via the OmniRoute scheme (HMAC-SHA256 with `API_KEY_SECRET`). Requires patching the DB schema directly — fragile across upgrades.
2. **Adopt OmniRoute's key model**: let OmniRoute mint a key on first boot, rotate the sops secret to point at the new key, accept the auth-model migration. This is the cleaner path and the one the upstream pre-flight's Q4 ("integration collision") already flagged as ✗.

### Endianness of route prefixes
The Luna-Server config currently uses hermes-router on port 8319. **OmniRoute does NOT support custom base port-of-call** beyond the three-port scheme. To preserve the `127.0.0.1:8319` endpoint, you must put a reverse proxy in front (Caddy/nginx mapping `:8319 → 127.0.0.1:20128`). Cleaner: rename the consumer to `:20128` and let the loopback bind do its job.

## 5. Nix flake / module integration approach

### Recommended shape (no upstream `nixosModules.default` exists)

```nix
# hosts/Luna-Server/ai/omniroute.nix
{ inputs, ... }:
{
  nixos.hosts."Luna-Server" =
    { config, lib, pkgs, ... }:
    let
      # Pin upstream tarball — `npm pack` the 3.8.50 release, build via npm.
      # Avoid the dev-shell flake; package the published npm tarball directly.
      omniroute = pkgs.stdenv.mkDerivation {
        pname = "omniroute";
        version = "3.8.50";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/omniroute/-/omniroute-3.8.50.tgz";
          hash = "sha256-…";  # compute via `nix-prefetch-url --unpack <url>`
        };
        # Standalone bundle already exists in the tarball; no build needed.
        # But better-sqlite3 + tls-client-node native modules MUST be rebuilt.
        nativeBuildInputs = [ pkgs.nodejs_24 pkgs.python3 pkgs.pkg-config ];
        buildPhase = ''
          npm rebuild better-sqlite3 tls-client-node --build-from-source
        '';
        installPhase = ''
          mkdir -p $out
          cp -r ./* $out/
          chmod -R u+w $out/node_modules
        '';
      };
    in {
      sops.secrets.omniroute_jwt_secret = { … };
      sops.secrets.omniroute_api_key_secret = { … };
      sops.secrets.omniroute_storage_encryption_key = { … };
      sops.secrets.omniroute_initial_password = { … };
      sops.secrets.omniroute_proxy_api_key = { … };  # canonical caller key

      sops.templates.omniroute-server-env = {
        content = ''
          JWT_SECRET=${config.sops.placeholder.omniroute_jwt_secret}
          API_KEY_SECRET=${config.sops.placeholder.omniroute_api_key_secret}
          STORAGE_ENCRYPTION_KEY=${config.sops.placeholder.omniroute_storage_encryption_key}
          INITIAL_PASSWORD=${config.sops.placeholder.omniroute_initial_password}
          OMNIROUTE_API_KEY=${config.sops.placeholder.omniroute_proxy_api_key}
        '';
        owner = "omniroute";
        group = "omniroute";
        mode = "0400";
        restartUnits = [ "omniroute.service" ];
      };

      users.users.omniroute = {
        isSystemUser = true;
        group = "omniroute";
        home = "/var/lib/omniroute";
        createHome = false;
      };
      users.groups.omniroute = { };

      systemd.services.omniroute = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        environment = {
          HOST = "127.0.0.1";
          PORT = "20128";
          DASHBOARD_PORT = "20128";
          API_PORT = "20128";
          LIVE_WS_HOST = "127.0.0.1";
          LIVE_WS_PORT = "20132";
          OMNIROUTE_MEMORY_MB = "2048";
          DATA_DIR = "/var/lib/omniroute";
          NODE_ENV = "production";
        };
        serviceConfig = {
          User = "omniroute";
          Group = "omniroute";
          StateDirectory = "omniroute";
          StateDirectoryMode = "0700";
          WorkingDirectory = "/var/lib/omniroute";
          EnvironmentFile = config.sops.templates.omniroute-server-env.path;
          ExecStart = "${omniroute}/bin/omniroute serve --no-open --no-tray";
          Restart = "on-failure";
          RestartSec = "5s";
          # ⚠ Next.js + native modules + persistent SQLite + npm-managed
          # node_modules require sandbox relaxation vs. hermes-router.
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ "/var/lib/omniroute" ];
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          CapabilityBoundingSet = "";
          AmbientCapabilities = "";
          # NOT settable on this stack:
          # - SystemCallFilter — risky with Next 16 / Node 22 native bindings
          # - MemoryDenyWriteExecute — incompatible with better-sqlite3 JIT
        };
      };
    };
}
```

### Regression test shape (mirror `tests/server-hermes-extensions-regressions.py`)
- Pin npm tarball hash + version in module
- Assert bind address is `127.0.0.1`
- Assert `allowedTCPPorts` does NOT contain `20128` / `20129` / `20132`
- Assert sops template present with all five keys
- Assert sops file exists in nixos-secrets snapshot

### Replacement vs parallel
**Recommendation**: keep `hermes-router` running on `:8319` and stand OmniRoute up in **parallel** on `:20128` (loopback-only, firewalled off) until consumer traffic is migrated. The skill `nixos-server-extension` is explicit: "Push is a publish action; publishing requires proof." For a 290-provider, ~55 MB `src/` replacement, the proof cycle is days, not minutes.

## 6. Security / hardening constraints

### Hard ceiling (mirrors pre-flight Q3 — still ✗ in 2026-08-07)

| Surface | hermes-router | OmniRoute upstream |
|---|---|---|
| Lines of code (source) | ~6,700 LOC | ~55 MB `src/` (~160k LOC) |
| Native modules at runtime | 0 | better-sqlite3, tls-client-node, optional onnxruntime, sqlite-vec |
| `ProtectSystem=strict` viable | ✓ | ⚠ viable; tls-client-node's `dlopen` is the main blocker |
| `CapabilityBoundingSet=""` viable | ✓ | ✓ |
| `RestrictNamespaces=true` viable | ✓ | ✓ |
| `RestrictAddressFamilies=[AF_INET AF_INET6 AF_UNIX]` viable | ✓ | ✓ |
| `SystemCallFilter=@system-service` viable | ✓ | ⚠ needs allowlist for node-gyp binding code paths |
| `MemoryDenyWriteExecute=true` viable | ✓ | ✗ — better-sqlite3 + sqlite-vec use JIT; tls-client-node's TLS state machine also writes |
| `PrivateDevices=true` viable | ✓ | ✓ |
| `ProtectKernelModules=true` viable | ✓ | ✓ |
| Total credential surface (provider keys stored at rest) | ~12 (single-user) | 290 providers × N keys each — **orders of magnitude** larger credential blast radius |
| LocalOnly route guard | N/A (Flask) | 23-prefix deny-list (`src/server/authz/routeGuard.ts:30-58`) with peer-stamp token validation (`management.ts:28-41`) — **better than hermes-router** if the peer-stamp survives |
| WebSocket CSRF / Origin enforcement | N/A | `LIVE_WS_ALLOWED_ORIGINS` default = 2 loopback origins only (`docker-compose.yml:43`) |

### What's BETTER than hermes-router
- 3-tier route guard (LOCAL_ONLY / ALWAYS_PROTECTED / MANAGEMENT) — real RBAC model
- AES-256-GCM at-rest encryption of provider credentials with versioned key rotation
- Per-key scopes (`manage`, `read:health`, `execute:completions`, etc.) with HMAC-signed keys
- Audit log of administrative actions (`SECURITY.md:147-149`)
- Guardrails: prompt-injection detector + PII redactor (fail-open, configurable)
- WebSocket Origin allow-list (defaults safe)

### What's WORSE
- **Build-time network egress** is mandatory: `tls-client-node`'s `postinstall.js` fetches a platform `.so` from `github.com/bogdanfinn/tls-client/releases` on every build (Dockerfile:69-78). Hermes-router has no equivalent. Reproducible Nix builds need to either (a) pin the postinstall fetch with `NIX_PATH`/vendor the binary, or (b) wrap the postinstall call in a pinned script that fails closed.
- **Socket.dev/Snyk false positives**: `SECURITY.md:219-240` explicitly notes the embedded bundle flags as malware-pattern, with mitigation via `OMNIROUTE_BUILD_PROFILE=minimal npm run build` (`package.json:93`). The Nix build should use this profile unless you need the four stripped modules (MITM cert install, Zed keychain, Cloud Sync, 9router installer).
- **Per-provider native modules**: `sqlite-vec`, `@huggingface/transformers`, `@tensorflow/tfjs`, `js-tiktoken` are optional deps. If you opt in (e.g. for semantic memory), the build grows ~316 MB (ONNX runtime CUDA). Nix build times will balloon.
- **No upstream `nixosModules.default`**: every Nix packaging decision is custom. Future upstream breaking changes land without warning.

### Provenance (still ✗ per pre-flight)
`SECURITY.md:220` quotes the ROADMAP: "publish provenance (OIDC) rehearsal" — not shipped. Sigstore/OIDC attestation is still a v3.8.57 roadmap item. Tarball integrity relies on npm registry SHA alone. Pin-via-sha256 + audit-with-`npm audit` is the floor, not the ceiling.

## 7. Migration requirements from 127.0.0.1:8319

### Stage 0 — Pre-flight (1 commit, no activation)
1. Add `omniroute` flake input pinned to a specific npm tarball SHA (NOT a git rev — upstream `prepublishOnly` is the source of truth).
2. Add `hosts/Luna-Server/ai/omniroute.nix` (above) but with `enable = false`.
3. Add the 5 new sops secrets to `nixos-secrets` repo (push separately, then `nix flake lock --update-input nixos-secrets`).
4. Add `tests/server-omniroute-regressions.py` mirroring hermes-router's test shape.
5. `nix flake check --no-build` + `just dry Luna-Server` green.

### Stage 1 — Shadow (1 commit, hermes-router stays primary)
1. Enable `omniroute.service` on `127.0.0.1:20128`, firewalled off.
2. Manually start the server, mint an API key, capture the key in sops.
3. Update `tests/server-omniroute-regressions.py` to assert the live port is up.
4. Smoke test the four canonical hermes-router consumer routes against `:20128`:
   - `POST /v1/chat/completions` (curl with bearer key)
   - `POST /v1/messages` (Anthropic SDK shape)
   - `GET /v1/models` (curl, no auth)
   - `POST /v1/embeddings` (curl with bearer key)
5. `just deploy Luna-Server`, verify both `:8319` and `:20128` respond.

### Stage 2 — Consumer migration (1 commit per consumer)
1. Update `modules/ai/hermes-mobile-bridge.nix` and `hosts/Luna-Server/ai/hermes-router.nix:327-333` — replace `ROUTER_API_KEY` with `OMNIROUTE_API_KEY` in `/etc/pam/environment`, plus rework hermes-agent's `key_env` resolution to read both names.
2. Update `Justfile` / deploy scripts that pin the old port.
3. Update regression tests under `tests/server-hermes-extensions-regressions.py` to assert the new port.

### Stage 3 — Decommission hermes-router (1 commit)
1. Disable `hermes-router.service` (do NOT delete yet — rollback path).
2. Remove `hermes-router.nix` from `flake.nix`'s module imports.
3. After 7 days of green, drop the file.

### Specific binding-affecting items the prior pre-flight flagged (still ✗ today)
- `ROUTER_API_KEY` / `MNEMOSYNE_*` env in `/etc/pam/environment` (`hermes-router.nix:327-333`) — **NOT** honored by OmniRoute. Need parallel `OMNIROUTE_API_KEY` line + hermes-agent resolution rework.
- `CODEX_MODEL` / `ZAI_MODEL` / `KIMI_MODEL` / `NEMOTRON_*` env in the systemd `environment` block — OmniRoute has its own provider catalog, configured via dashboard or `omniroute setup` CLI subcommands. The systemd-env override pattern doesn't translate; you'd set provider defaults via the dashboard and persist them in `storage.sqlite` instead.
- The `installHermesServerExtensions` onboarding script (`hermes-router.nix:86-251`) configures Hermes custom providers via `hermes config set` — needs reworking to point at the new `OMNIROUTE_API_KEY` and `OMNIROUTE_BASE_URL` (default `http://127.0.0.1:20128/v1`).

## 8. Honest recommendation

**Do not replace** in a single deploy. The pre-flight's ✗ verdict on Q2 (provenance), Q3 (hardening ceiling), and Q4 (4+ integration points) **still holds at 976d670**. The line-count and credential-surface delta are larger than hermes-router by ~10x and ~25x respectively; the build-time network egress on `tls-client-node` is a new failure mode hermes-router doesn't have; the auth model breaks 4 declarative integrations.

**If the user has a specific pain that motivates the replacement** (e.g. they need prompt-injection guardrails, or 290 providers, or per-key scopes), the above 4-stage migration is the minimum-correct path. Stage 1 (shadow) alone is a meaningful deliverable — it gets the Nix module + sops + sandbox + regression test shipped without touching live traffic.

**If the user is open to a smaller delta**, consider whether the actual need is:
- **A dashboard / metrics UI on top of hermes-router** → ~150 LOC webui read-only mode, not a router replacement.
- **Anthropic-format `/v1/messages` support** → ~30 LOC to hermes-router to translate the Anthropic request shape to its existing OpenAI path (the upstream already has `_anthropic_request_to_openai` at `router.py:5824`).
- **More providers / fallback chains** → those are upstream-only; either contribute to hermes-router or fork.

The OmniRoute replacement is the right call **only** if the user explicitly opts in to the 4-stage migration cost and accepts the sandbox relaxations.

---

## File / line citations (one-call reproducibility)

| Fact | File:line |
|---|---|
| Repo HEAD | `git rev-parse HEAD` → `976d670ff3a7712df0c695f13095c43eace5e29b` |
| Node engine constraint | `/tmp/OmniRoute-inspect/package.json:54` |
| Build-time egress (tls-client-node) | `/tmp/OmniRoute-inspect/Dockerfile:69-86` |
| Mandatory native rebuilds | `/tmp/OmniRoute-inspect/Dockerfile:79-86` |
| Default ports | `/tmp/OmniRoute-inspect/.env.example:74-83` |
| Data dir resolution | `/tmp/OmniRoute-inspect/scripts/build/bootstrap-env.mjs:36-51` |
| Auto-generated secrets | `/tmp/OmniRoute-inspect/scripts/build/bootstrap-env.mjs:185-222` |
| Encryption-key refuse-to-overwrite | `/tmp/OmniRoute-inspect/scripts/build/bootstrap-env.mjs:196-208` |
| API port resolution | `/tmp/OmniRoute-inspect/scripts/build/runtime-env.mjs:107-126` |
| Heap ceiling auto-calibration | `/tmp/OmniRoute-inspect/scripts/build/runtime-env.mjs:32-37` |
| `OMNIROUTE_BASE_PATH` build-time | `/tmp/OmniRoute-inspect/Dockerfile:98-101`, `next.config.mjs:105,111` |
| Server entry point (standalone) | `/tmp/OmniRoute-inspect/bin/cli/commands/serve.mjs:34-36, 134-160` |
| API routes — chat completions | `/tmp/OmniRoute-inspect/src/app/api/v1/chat/completions/route.ts:1` |
| API routes — messages (Anthropic) | `/tmp/OmniRoute-inspect/src/app/api/v1/messages/route.ts:1` |
| API routes — embeddings | `/tmp/OmniRoute-inspect/src/app/api/v1/embeddings/route.ts:1` |
| API routes — models | `/tmp/OmniRoute-inspect/src/app/api/v1/models/route.ts:25` |
| API routes — responses (OpenAI Responses) | `/tmp/OmniRoute-inspect/src/app/api/v1/responses/route.ts:1` |
| API auth flow | `/tmp/OmniRoute-inspect/src/shared/utils/apiAuth.ts:172-181` |
| API key extraction | `/tmp/OmniRoute-inspect/src/sse/services/auth.ts:2435+` |
| LOCAL_ONLY route deny-list | `/tmp/OmniRoute-inspect/src/server/authz/routeGuard.ts:30-58` |
| Peer-stamp locality enforcement | `/tmp/OmniRoute-inspect/src/server/authz/policies/management.ts:28-41` |
| Built-in encryption (AES-256-GCM) | `/tmp/OmniRoute-inspect/SECURITY.md:55-66` |
| Audit log scope | `/tmp/OmniRoute-inspect/SECURITY.md:147-149` |
| Guardrails (injection / PII) | `/tmp/OmniRoute-inspect/SECURITY.md:78-94` |
| WebSocket Origin allowlist | `/tmp/OmniRoute-inspect/docker-compose.yml:43` |
| CSP / security headers | `/tmp/OmniRoute-inspect/next.config.mjs:12-58` |
| Minimal-build profile (skip 4 privileged modules) | `/tmp/OmniRoute-inspect/package.json:93` |
| Existing hermes-router target (port, sandbox, env) | `/home/luna/nixos/hosts/Luna-Server/ai/hermes-router.nix:339-412` |
| Existing hermes-router regression test | `/home/luna/nixos/tests/server-hermes-extensions-regressions.py:1-100` |
| Existing hermes-router admin-surface patch | `/home/luna/nixos/hosts/Luna-Server/ai/patches/hermes-router-disable-admin-surfaces.patch:1-50` |
| Pre-flight prior verdict | `/home/luna/.hermes/skills/software-development/nix-server-extension/references/nix-server-feasibility-preflight.md:1-180` |