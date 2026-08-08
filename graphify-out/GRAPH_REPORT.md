# Graph Report - /home/luna/nixos  (2026-08-07)

## Corpus Check
- 63 files · ~58,756 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 337 nodes · 388 edges · 60 communities (34 shown, 26 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 1 edges (avg confidence: 0.5)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Community 0
- Community 1
- Community 2
- Community 3
- Community 4
- Community 5
- Community 6
- Community 7
- Community 8
- Community 9
- Community 10
- Community 11
- Community 12
- Community 13
- Community 14
- Community 15
- Community 16
- Community 17
- Community 18
- Community 19
- Community 20
- Community 21
- Community 22
- Community 23
- Community 24
- Community 25
- Community 26
- Community 27
- Community 28
- Community 29
- Community 30
- Community 31
- Community 32
- Community 33
- Community 34
- Community 35
- Community 36
- Community 37
- Community 38
- Community 39
- Community 41
- Community 45

## God Nodes (most connected - your core abstractions)
1. `nixos.modules.common (role)` - 30 edges
2. `nixos.hosts.TSBW-W01800 (host)` - 29 edges
3. `header()` - 27 edges
4. `nixos.hosts.UwU-Server (host)` - 15 edges
5. `run()` - 12 edges
6. `nixos.hosts.UwU (host)` - 11 edges
7. `main()` - 7 edges
8. `nixos.hosts.OwO-Family (host)` - 7 edges
9. `register()` - 6 edges
10. `main()` - 6 edges

## Surprising Connections (you probably didn't know these)
- `bootstrap-network-regressions.sh script` --calls--> `host_key_sets_overlap()`  [EXTRACTED]
  tests/bootstrap-network-regressions.sh → scripts/bootstrap-host.sh
- `bootstrap-network-regressions.sh script` --calls--> `filter_host_keys_to_overlap()`  [EXTRACTED]
  tests/bootstrap-network-regressions.sh → scripts/bootstrap-host.sh
- `bootstrap-network-regressions.sh script` --calls--> `network_cidr_for_target()`  [EXTRACTED]
  tests/bootstrap-network-regressions.sh → scripts/bootstrap-host.sh

## Import Cycles
- None detected.

## Communities (60 total, 26 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.10
Nodes (35): color_check(), header(), json_output(), run(), run_silent(), section_bridge(), section_connectivity(), section_conntrack() (+27 more)

### Community 4 - "Community 4"
Cohesion: 0.26
Nodes (10): exercise(), exercise_parent_replacement_race(), exercise_response_url_safety(), exercise_symlinked_root(), FakeResponse, generated_image(), load_plugin(), main() (+2 more)

### Community 5 - "Community 5"
Cohesion: 0.17
Nodes (12): BOOT_VERIFY_TEST_MODE, CREATE_CALLED, EFI_STATE, EFIVARS_PATH, FAKE_DISK, FAKE_ESP, OTHER_DISK, PARTUUID (+4 more)

### Community 7 - "Community 7"
Cohesion: 0.26
Nodes (8): confirm_installer_host_key(), filter_host_keys_to_overlap(), host_key_sets_overlap(), network_cidr_for_target(), bootstrap-host.sh script, usage(), PATH, bootstrap-network-regressions.sh script

### Community 8 - "Community 8"
Cohesion: 0.33
Nodes (5): fail(), is_canonical_store_artifact(), is_canonical_store_root(), resolve_system_profile(), verify-installed-boot.sh script

### Community 9 - "Community 9"
Cohesion: 0.54
Nodes (7): NoReturn, add_reference(), fail(), main(), Path, register(), rule_ranges()

### Community 11 - "Community 11"
Cohesion: 0.25
Nodes (6): iter_nix_files(), parse_manifest(), parse_walker_regexes(), Path, Return the ``dendriticExceptions`` attrset from flake.nix., Return every ``builtins.match`` regex the collectModules body uses. The…

### Community 12 - "Community 12"
Cohesion: 0.57
Nodes (7): assignments(), main(), prior_store_path(), CompletedProcess, Path, require(), run()

### Community 13 - "Community 13"
Cohesion: 0.60
Nodes (5): fail(), reject(), require(), require_condition(), require_pattern()

### Community 15 - "Community 15"
Cohesion: 0.70
Nodes (4): fail(), notify_error(), prompt_password(), set-private-password-hash.sh script

### Community 16 - "Community 16"
Cohesion: 0.90
Nodes (4): fail(), reject(), require(), bootstrap-host-regressions.sh script

### Community 17 - "Community 17"
Cohesion: 0.40
Nodes (4): check(), non_comment_lines(), Record a pass/fail check; print a one-liner., Return lines of `body` with comment lines stripped. Disko configs are line-…

### Community 18 - "Community 18"
Cohesion: 0.60
Nodes (4): main(), CompletedProcess, Path, run_helper()

### Community 19 - "Community 19"
Cohesion: 0.40
Nodes (3): Path, Return the secrets repo root, prefer the value injected via env., resolve_sops_root()

### Community 20 - "Community 20"
Cohesion: 0.50
Nodes (3): JUST_TEST_LOG, PATH, justfile-argument-regressions.sh script

### Community 22 - "Community 22"
Cohesion: 1.00
Nodes (3): assert_eq(), fail(), review-regressions.sh script

## Knowledge Gaps
- **30 isolated node(s):** `gpu-dpm.sh script`, `power-change.sh script`, `usb-autosuspend.sh script`, `setup-deep-live-cam.sh script`, `update-animejanai.sh script` (+25 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **26 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `nixos.modules.common (role)` connect `Community 1` to `Community 3`?**
  _High betweenness centrality (0.019) - this node is a cross-community bridge._
- **What connects `gpu-dpm.sh script`, `power-change.sh script`, `usb-autosuspend.sh script` to the rest of the system?**
  _30 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.09830866807610994 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.05714285714285714 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.06666666666666667 - nodes in this community are weakly interconnected._
- **Should `Community 3` be split into smaller, more focused modules?**
  _Cohesion score 0.125 - nodes in this community are weakly interconnected._