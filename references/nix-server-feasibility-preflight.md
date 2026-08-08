# Nix server-extension pre-flight feasibility check (OmniRoute, 2026-08-07)

Worked example of the **should-we-even-wrap-this?** evaluation that runs
BEFORE the packaging work begins. The OmniRoute session is the canonical
instance — the user asked "does this have a flake or so" and explicitly
told the agent not to implement until a review-agent on their nix config
finishes. So the deliverable for the pre-flight was a structured
feasibility answer, not a patch.

## When to run this gate

Before any of the existing paths in this skill (nixpkgs module, flake
input + custom module, pip-venv, oci-container), answer four questions
in order. If any answer is "this is going to be expensive," stop and
report to the user before sinking time into a packaging prototype.

## The four-question gate

### Q1. Upstream Nix packaging posture

Search the four canonical places. Any "yes" makes packaging straightforward.
All "no" means you're the first to wrap it — flag that explicitly to the
user before committing.

```bash
# 1a. nixpkgs
curl -sIL "https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/<x>/<name>/package.nix" | head -1
# 2xx = in nixpkgs; 404 = absent

# 1b. upstream repo for a flake.nix
git clone --depth=1 --filter=blob:none --sparse <repo-url>
cd <repo> && grep -riE "(flake|nix|nixpkgs)" . --include="*.md" --include="*.nix" 2>/dev/null | grep -v node_modules

# 1c. community flakes (GitHub code search needs auth; web search is the fallback)
# Search: "<name> flake.nix", "<name> nixpkgs", "<name> nix package"

# 1d. similar projects' packaging (if a close cousin exists, that signals ecosystem norms)
# e.g. for an AI router: check LiteLLM, 9router, etc.
```

**OmniRoute result (2026-08-07):** Not in nixpkgs. No flake in the
upstream repo. No community flakes surfaced on web search. 9router
(close cousin, also Next.js + npm) also has no flake. The ecosystem
pattern is npm + Docker, not Nix. → flag to user as "you'd be the first
to wrap this."

### Q2. Provenance / declarative pinning

You need to pin a specific rev + sha256 of upstream code at Nix build
time, and the upstream must publish artifacts whose integrity is
checkable. Concrete signals:

| Signal | Good | Bad |
|---|---|---|
| Source distribution | Tarballs with sha256 in releases | npm-only (rotates weekly) |
| Build pipeline | `make` / `cmake` / standard build | npm postinstall scripts |
| Native modules | None or pure-Python | sqlite-vec, prisma engines, playwright (these need buildPhase in Nix, slow + flaky) |
| Provenance | Sigstore / OIDC attestation published | Internal-only (ROADMAP item, not shipped) |
| Release cadence | Predictable (e.g. monthly) | Weekly with breaking native-dep bumps |

**OmniRoute result:** npm-only distribution, weekly releases (3.8.50 →
3.8.57 roadmap), npm postinstall scripts (`postinstall.mjs`,
`fixTlsClientNodeBinary.mjs`, `fixPlaywrightAndroid.mjs` = arbitrary
code execution on every install), native modules (sqlite-vec, prisma
engines). ROADMAP line item 3.8.57 says "publish provenance (OIDC)
rehearsal" — not shipped. → you lose the hermes-router-style "any drift
breaks the build" property.

### Q3. Attack surface vs. hardening ceiling

Your existing systemd sandbox template (`ProtectSystem=strict`,
`ProtectHome=true`, `PrivateTmp`, `ProtectKernel*`, `RestrictNamespaces`,
`RestrictSUIDSGID`, `LockPersonality`, `CapabilityBoundingSet=""`,
`ProcSubset=pid`, `RestrictAddressFamilies` narrowed) is appropriate for
~500-1000 LOC focused services. Anything substantially larger, or
anything that needs native modules / dynamic code loading / persistent
caches, will force sandbox relaxation.

Rough heuristic:
- **Python Flask app, <2k LOC, no native deps** → sandbox as-is works
- **Static Go/Rust binary, no dynamic loading** → sandbox as-is works
- **Next.js / Express + native modules + persistent SQLite** → sandbox
  must relax substantially (writable /tmp, broader AF, no
  `PrivateDevices`, may need `ProtectSystem=full` instead of `strict`).
  Each relaxation is a new thing to audit.

**OmniRoute result:** Next.js 16 + React 19 + prisma + sqlite-vec +
playwright optional + npm postinstall pipeline. Cannot run under the
current sandbox. You'd add a larger, less-hardened service to your
fleet, ~100x the credential surface of your current hermes-router.

### Q4. Integration collision with existing stack

List every place your current nixconfig touches the service being
replaced. For each, decide: would the replacement honor it as-is, need
adaptation, or break?

Common collision points to enumerate:
- systemd unit env vars (`<NAME>_MODEL`, `CODEX_MODEL`, `LOCAL_BASE_URL`,
  etc.) — does the replacement read these?
- `/etc/pam/environment` keys (e.g. `ROUTER_API_KEY`) — does the
  replacement use the same auth surface or invent its own?
- Existing sops secrets — does the replacement consume the same shape
  (API keys, tokens) or need a parallel secret tree?
- Existing webui / dashboard — overlap or duplication?
- Existing CLI tool integration (hermes-agent's `providers.<name>`
  registry, custom-provider resolution) — does the replacement slot in
  or require rewiring?

**OmniRoute result:** 4 integration points would break / need rewrite
(a) `ROUTER_API_KEY` in `/etc/pam/environment`, (b) `MNEMOSYNE_*`
embedding env, (c) `CODEX_MODEL=<custom-chain>` env, (d) the
`installHermesServerExtensions` onboarding script. None of OmniRoute's
internals honor these. Replacement is not drop-in.

## Decision matrix

Score each Q as ✓ (works as-is) / ◐ (needs adaptation) / ✗ (major rework or
blocks the change):

| Q | ✓ | ◐ | ✗ | Notes |
|---|---|---|---|---|
| 1. Nix posture | In nixpkgs | Upstream flake exists, you wrap | Nothing — you build from scratch | Drives packaging cost: hours vs days vs weeks |
| 2. Provenance | Tarballs + sigstore | Git rev + sha256 (your pattern) | npm only, weekly, native modules | Determines whether pin-then-deploy still works |
| 3. Hardening | Sandbox as-is | Selective relaxation needed | Must rewrite sandbox profile | Determines attack-surface delta |
| 4. Integration | Drop-in replacement | Re-implement 1-2 surface points | Re-implement 4+ surface points | Determines total scope |

If 3+ of 4 are ✗, recommend not replacing. If 1-2 are ◐ and the user has a
concrete pain the replacement solves, proceed with a packaging prototype
(only after user OK).

## What to deliver back to the user

For each Q, give the specific evidence (URLs, sha256s, file paths in
their own repo, line counts). Do not summarize with "looks hard" —
that's not actionable. The user wants the data so they can decide.

Structure the reply as:
1. Q1 result + evidence
2. Q2 result + evidence
3. Q3 result + evidence
4. Q4 result + evidence
5. Decision matrix
6. Honest cost estimate if they proceed
7. Alternatives worth considering (one level down from the candidate)
8. Recommendation with a specific next-step they can greenlight

The "alternatives" step is what makes the analysis useful — most
"should I adopt X?" questions dissolve into "adopt something at a
different altitude." For OmniRoute that meant LiteLLM Proxy (smaller
surface, similar capability) or "add ~150 LOC to your existing
hermes-router" (lowest cost, addresses the dashboard gap directly).

## Pitfalls

### Don't run the gate and then immediately implement

The user asked you to investigate, not to act. If you discover the
candidate is not viable, deliver the negative answer with evidence.
The implementation never starts. If you're tempted to "while I'm here,
let me also write the Nix module" — stop. Re-read the user's last
message.

### Don't confuse "popularity" with "Nix-fit"

A project with 290 provider integrations, 25k tests, weekly releases,
and a flashy README can still be a poor Nix fit if it ships via npm,
relies on native modules, and lacks provenance. Popularity drives
adoption intent; Nix-fit drives adoption cost. Report them separately.

### Don't skip Q4 even if Q1-Q3 look fine

A candidate that is trivial to package AND well-hardened AND
provenance-stable can STILL be the wrong choice if it breaks your
integration points. The "drop-in replacement" assumption is the most
expensive mistake in this class of work — it turns a 3-day packaging
task into a 3-week integration rewrite.

### Don't claim "no Nix posture" without checking all four sources

A negative result on nixpkgs + upstream repo + community search +
similar-projects is strong evidence. A negative on just nixpkgs is
inconclusive — many projects are wrapped by third parties before
nixpkgs catches up.
