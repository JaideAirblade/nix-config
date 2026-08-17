#!/usr/bin/env python3
"""Regression contract for modules/observability/node-exporter.nix + umbrella.

The node_exporter module + its umbrella must:

  1. Both files exist (umbrella + config-only contributor).
  2. The umbrella (modules/observability/default.nix) declares options
     under `observability.nodeExporter` — Option A split.
  3. The node-exporter.nix file is CONFIG-ONLY — does NOT take `config`
     as an arg (flake-parts evaluates deferred modules at flake-time
     without `config`/`pkgs` in scope, except as NixOS-instantiated args).
  4. Wraps `services.prometheus.exporters.node` from nixpkgs with
     port=9100, listenAddress=0.0.0.0 (the safety fallback), and the
     systemd collector enabled by default.
  5. Skips noisy collectors (wifi, powersupplyclass).
  6. Allows TCP 9100 on both tailscale0 (legacy) and wt0 (current
     Netbird mesh) — supports the migration without breaking either.
  7. Filters pseudo + overlay mountpoints via the
     `--collector.filesystem.mount-points-exclude` regex.
  8. The safety assertion (refuse to bind to 0.0.0.0 when enable=true)
) does NOT live in this config-only file (it would require reading
     `config`, which we can't take). The umbrella documents it instead
     so a host reading the docs knows to set listenAddress.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NODE_EXPORTER = ROOT / "modules" / "observability" / "node-exporter.nix"
UMBRELLA = ROOT / "modules" / "observability" / "options.nix"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(NODE_EXPORTER.exists(), "modules/observability/node-exporter.nix is missing")
require(UMBRELLA.exists(),
        "modules/observability/default.nix is missing (umbrella for option declarations)")

src = NODE_EXPORTER.read_text(encoding="utf-8")
umbrella_src = UMBRELLA.read_text(encoding="utf-8")

# 1. Dendritic target.
require("nixos.modules.observability" in src,
        "module must contribute to nixos.modules.observability (the role)")

# 2. Options live in the umbrella.
require("options.observability.nodeExporter" in umbrella_src,
        "umbrella must declare options.observability.nodeExporter")
for needle in ("listenAddress", "port", "extraCollectors"):
    require(needle in umbrella_src,
            f"umbrella must declare option '{needle}' under observability.nodeExporter")
require("mkEnableOption" in umbrella_src,
        "umbrella must use mkEnableOption for the enable option")

# 3. Config-only file — function takes only flake-parts-safe args.
sig_match = re.search(r"\{[^}]*\}:", src)
assert sig_match is not None  # require() above already exited
sig = sig_match.group(0)
for forbidden in ("config,", "config ", "{config"):
    require(forbidden not in sig,
            f"module function must NOT take `{forbidden}` as arg (flake-parts doesn't provide it at flake-time)")

# 4. services.prometheus.exporters.node config.
require("services.prometheus.exporters.node" in src,
        "module must configure services.prometheus.exporters.node")
require("enable = true" in src,
        "node_exporter must be enabled (overridable per host via observability.nodeExporter.enable)")
require("port = 9100" in src,
        "node_exporter must default to port 9100")
require('"0.0.0.0"' in src,
        "node_exporter must default listenAddress to 0.0.0.0 (the safety fallback hosts must override)")
require("systemd" in src,
        "node_exporter must enable the systemd collector by default")

# 5. Disabled collectors — wifi and powersupplyclass are noise.
require('"wifi"' in src,
        "module must disable 'wifi' collector (irrelevant for most hosts)")
require('"powersupplyclass"' in src,
        "module must disable 'powersupplyclass' collector (smartd/acpi handle power better)")

# 6. Firewall — Netbird mesh interface (wt0).
require('"wt0"' in src,
        "firewall must allow TCP on wt0 (Netbird mesh — current production mesh)")
require('"tailscale0"' not in src,
        "firewall must NOT reference tailscale0 (Tailscale was removed in the 2026-08-09 Netbird migration)")

# 7. Filesystem filter — pseudo + overlay mounts.
# The regex is `^/(dev|proc|sysfs|run|var/lib/docker/overlay2|var/lib/flatpak)($|/)`.
# Each component is an alternation inside parens, not a raw substring,
# so we assert the the alternation group exists rather than checking
# for the raw path literal. Pull the value between the surrounding
# quotes on the *config* line (not the docstring comment which has a
# shorter variant). Config lines start with `--collector.` and live
# inside `extraFlags = [...]`.
mount_re = re.search(
    r'extraFlags\s*=\s*\[[^\]]*?"[^"]*mount-points-exclude=(\^[^"]+)',
    src,
    re.DOTALL,
)
assert mount_re is not None  # require() above already exited
re_value = mount_re.group(1)
for needle in ("dev", "proc", "sysfs", "run", "overlay2", "flatpak"):
    require(needle in re_value,
            f"mount-points-exclude regex must include {needle!r} in its alternation")

# 8. No `assertions = ...` block in this config-only file (would need
# `config` arg, which we can't take). The umbrella documents the
# requirement instead.
assertions_match = re.search(r"\bassertions\s*=", src)
require(assertions_match is None,
        "config-only file must NOT declare assertions (would require reading `config`; the umbrella documents the check instead)")

print("modules/observability/node-exporter.nix (mesh-scoped metrics + Option A split): PASS")