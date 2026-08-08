# Graph Report - .  (2026-08-07)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 345 nodes · 399 edges · 56 communities (39 shown, 17 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 1 edges (avg confidence: 0.5)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `1e3a7f89`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- net-report.sh
- AD Test Lab
- What You Must Do When Invoked
- 2026-07-24_150000-ad-test-lab.md
- minimax-plugin-security-runtime.py
- New Host Provisioning Plan (nixos-anywhere + disko)
- verify-installed-boot-regressions.sh
- nix-config
- bootstrap-host.sh
- graphify reference: extra exports and benchmark
- verify-installed-boot.sh
- register
- main
- Private Tailscale management mesh
- graphify reference: query, path, explain
- local-honcho-regressions.py
- set-private-password-hash.sh
- bootstrap-host-regressions.sh
- data-pool-layout-regressions.py
- run_helper
- resolve_sops_root
- graphify reference: add a URL and watch a folder
- graphify reference: commit hook and native CLAUDE.md integration
- graphify reference: incremental update and cluster-only
- justfile-argument-regressions.sh
- private-accounts-regressions.py
- review-regressions.sh
- graphify reference: GitHub clone and cross-repo merge
- graphify reference: transcribe video and audio
- torrent-stream.py
- set-private-password-hash-regressions.sh
- AGENTS.md
- CLAUDE.md
- extraction-spec.md
- gpu-dpm.sh
- power-change.sh
- usb-autosuspend.sh
- setup-deep-live-cam.sh
- update-animejanai.sh
- confirm-local-deploy.sh
- sister-sync-from-uwu.sh
- bootstrap-authenticity-regressions.sh
- private-pam-u2f-regressions.sh

## God Nodes (most connected - your core abstractions)
1. `header()` - 27 edges
2. `New Host Provisioning Plan (nixos-anywhere + disko)` - 13 edges
3. `run()` - 12 edges
4. `What You Must Do When Invoked` - 12 edges
5. `AD Test Lab` - 11 edges
6. `/graphify` - 10 edges
7. `Daily workflow` - 10 edges
8. `graphify reference: extra exports and benchmark` - 8 edges
9. `AD Test Lab Implementation Plan` - 8 edges
10. `main()` - 7 edges

## Surprising Connections (you probably didn't know these)
- `bootstrap-network-regressions.sh script` --calls--> `host_key_sets_overlap()`  [EXTRACTED]
  tests/bootstrap-network-regressions.sh → scripts/bootstrap-host.sh
- `bootstrap-network-regressions.sh script` --calls--> `filter_host_keys_to_overlap()`  [EXTRACTED]
  tests/bootstrap-network-regressions.sh → scripts/bootstrap-host.sh
- `bootstrap-network-regressions.sh script` --calls--> `network_cidr_for_target()`  [EXTRACTED]
  tests/bootstrap-network-regressions.sh → scripts/bootstrap-host.sh

## Import Cycles
- None detected.

## Communities (56 total, 17 thin omitted)

### Community 0 - "net-report.sh"
Cohesion: 0.10
Nodes (35): color_check(), header(), json_output(), run(), run_silent(), section_bridge(), section_connectivity(), section_conntrack() (+27 more)

### Community 1 - "AD Test Lab"
Cohesion: 0.07
Nodes (27): 1. Rebuild to enable libvirt, 2. Create the domain controller (from ISO), 3. Create the client base image (from ISO), AD Test Lab, Architecture, Can't reach the VM via SSH, Check lab status, Connect to the client (+19 more)

### Community 2 - "What You Must Do When Invoked"
Cohesion: 0.08
Nodes (24): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Interpreter guard for subcommands, Part A - Structural extraction for code files (+16 more)

### Community 3 - "2026-07-24_150000-ad-test-lab.md"
Cohesion: 0.10
Nodes (20): AD Test Lab Implementation Plan, Assumptions, → clones from base image, starts VM, Copy domain-join.ps1 from \\192.168.100.10\share or manually, Current Context, → destroys old VM, creates fresh clone from base, → enters domain admin credentials, joins domain, restarts, Full file tree after implementation (+12 more)

### Community 4 - "minimax-plugin-security-runtime.py"
Cohesion: 0.26
Nodes (10): exercise(), exercise_parent_replacement_race(), exercise_response_url_safety(), exercise_symlinked_root(), FakeResponse, generated_image(), load_plugin(), main() (+2 more)

### Community 5 - "New Host Provisioning Plan (nixos-anywhere + disko)"
Cohesion: 0.14
Nodes (13): Assumptions, Current Context, Full provisioning workflow (cheat sheet), New Host Provisioning Plan (nixos-anywhere + disko), Open Questions, Risks and Tradeoffs, Task 1: Add flake inputs for nixos-anywhere and disko, Task 2: Create a shared disko disk layout module (+5 more)

### Community 6 - "verify-installed-boot-regressions.sh"
Cohesion: 0.17
Nodes (12): BOOT_VERIFY_TEST_MODE, CREATE_CALLED, EFI_STATE, EFIVARS_PATH, FAKE_DISK, FAKE_ESP, OTHER_DISK, PARTUUID (+4 more)

### Community 7 - "nix-config"
Cohesion: 0.17
Nodes (11): Adding a new device, Architecture, Hosts, How it works, Luna automation trust boundary, nix-config, Provisioning a new device, Quick reference (+3 more)

### Community 8 - "bootstrap-host.sh"
Cohesion: 0.26
Nodes (8): confirm_installer_host_key(), filter_host_keys_to_overlap(), host_key_sets_overlap(), network_cidr_for_target(), bootstrap-host.sh script, usage(), PATH, bootstrap-network-regressions.sh script

### Community 9 - "graphify reference: extra exports and benchmark"
Cohesion: 0.22
Nodes (8): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000)

### Community 10 - "verify-installed-boot.sh"
Cohesion: 0.33
Nodes (5): fail(), is_canonical_store_artifact(), is_canonical_store_root(), resolve_system_profile(), verify-installed-boot.sh script

### Community 11 - "register"
Cohesion: 0.54
Nodes (7): NoReturn, add_reference(), fail(), main(), Path, register(), rule_ranges()

### Community 12 - "main"
Cohesion: 0.57
Nodes (7): assignments(), main(), prior_store_path(), CompletedProcess, Path, require(), run()

### Community 13 - "Private Tailscale management mesh"
Cohesion: 0.29
Nodes (6): Acceptance checks, Access model, Existing Luna account migration, One-time tailnet setup, Private Tailscale management mesh, Troubleshooting (learned 2026-08-05)

### Community 14 - "graphify reference: query, path, explain"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 15 - "local-honcho-regressions.py"
Cohesion: 0.60
Nodes (5): fail(), reject(), require(), require_condition(), require_pattern()

### Community 16 - "set-private-password-hash.sh"
Cohesion: 0.70
Nodes (4): fail(), notify_error(), prompt_password(), set-private-password-hash.sh script

### Community 17 - "bootstrap-host-regressions.sh"
Cohesion: 0.90
Nodes (4): fail(), reject(), require(), bootstrap-host-regressions.sh script

### Community 18 - "data-pool-layout-regressions.py"
Cohesion: 0.40
Nodes (4): check(), non_comment_lines(), Record a pass/fail check; print a one-liner., Return lines of `body` with comment lines stripped. Disko configs are line-…

### Community 19 - "run_helper"
Cohesion: 0.60
Nodes (4): main(), CompletedProcess, Path, run_helper()

### Community 20 - "resolve_sops_root"
Cohesion: 0.40
Nodes (3): Path, Return the secrets repo root, prefer the value injected via env., resolve_sops_root()

### Community 21 - "graphify reference: add a URL and watch a folder"
Cohesion: 0.50
Nodes (3): For /graphify add, For --watch, graphify reference: add a URL and watch a folder

### Community 22 - "graphify reference: commit hook and native CLAUDE.md integration"
Cohesion: 0.50
Nodes (3): For git commit hook, For native CLAUDE.md integration, graphify reference: commit hook and native CLAUDE.md integration

### Community 23 - "graphify reference: incremental update and cluster-only"
Cohesion: 0.50
Nodes (3): For --cluster-only, For --update (incremental re-extraction), graphify reference: incremental update and cluster-only

### Community 24 - "justfile-argument-regressions.sh"
Cohesion: 0.50
Nodes (3): JUST_TEST_LOG, PATH, justfile-argument-regressions.sh script

### Community 26 - "review-regressions.sh"
Cohesion: 1.00
Nodes (3): assert_eq(), fail(), review-regressions.sh script

## Knowledge Gaps
- **132 isolated node(s):** `gpu-dpm.sh script`, `power-change.sh script`, `usb-autosuspend.sh script`, `setup-deep-live-cam.sh script`, `update-animejanai.sh script` (+127 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **17 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What connects `gpu-dpm.sh script`, `power-change.sh script`, `usb-autosuspend.sh script` to the rest of the system?**
  _132 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `net-report.sh` be split into smaller, more focused modules?**
  _Cohesion score 0.09830866807610994 - nodes in this community are weakly interconnected._
- **Should `AD Test Lab` be split into smaller, more focused modules?**
  _Cohesion score 0.07142857142857142 - nodes in this community are weakly interconnected._
- **Should `What You Must Do When Invoked` be split into smaller, more focused modules?**
  _Cohesion score 0.08 - nodes in this community are weakly interconnected._
- **Should `2026-07-24_150000-ad-test-lab.md` be split into smaller, more focused modules?**
  _Cohesion score 0.09523809523809523 - nodes in this community are weakly interconnected._
- **Should `New Host Provisioning Plan (nixos-anywhere + disko)` be split into smaller, more focused modules?**
  _Cohesion score 0.14285714285714285 - nodes in this community are weakly interconnected._