# Justfile — shortcuts for the NixOS flake at ~/nixos.
# Run `just` with no args to list recipes. `just <recipe>` runs one.
#
# Host is auto-detected from the system hostname, so `just deploy` works
# on any machine in the flake without specifying the target. Override with
# `just deploy host=NAME` (e.g. `just deploy host=TSBW-W01800`).
host := `hostname`

# ── deploy / build ──────────────────────────────────────────────
# Deploy the current host (auto-detected). Override: `just deploy host=TSBW-W01800`
deploy host=host:
  nixos-rebuild switch --flake .#{{host}} --elevate=sudo

# Build the full system closure without activating — safest pre-check.
dry host=host:
  nixos-rebuild dry-build --flake .#{{host}}

# Build a throwaway VM from the config (no host changes). Result link: ./result
vm host=host:
  nixos-rebuild build-vm --flake .#{{host}}

# Verbose deploy with full trace + build logs (for debugging eval errors).
debug host=host:
  nixos-rebuild switch --flake .#{{host}} --elevate=sudo --show-trace --print-build-logs --verbose

# ── flake inputs ──────────────────────────────────────────────────
# Update all flake inputs, then deploy the current host.
up host=host:
  nix flake update
  nixos-rebuild switch --flake .#{{host}} --elevate=sudo

# Update a single input, then deploy the current host. usage: `just upp i=hermes-agent`
upp i="" host=host:
  nix flake update {{i}}
  nixos-rebuild switch --flake .#{{host}} --elevate=sudo

# Show what changed in flake.lock vs the last commit.
diff:
  git diff flake.lock

# ── inspection / debugging ─────────────────────────────────────
# Nix REPL loaded with this flake in scope — `:lf .` then TAB through config.
repl:
  nix repl --file flake:nixpkgs

# Show every generation of the system profile.
history:
  nix profile history --profile /nix/var/nix/profiles/system

# Why is package X installed? Opens nix-tree on all gc-roots.
why:
  nix shell nixpkgs#nix-tree nixpkgs#ripgrep --command sh -c "nix-store --gc --print-roots | rg -v '/proc/' | rg -Po '(?<= -> ).*' | xargs -o nix-tree"

# ── cleanup ──────────────────────────────────────────────────────
# Drop generations older than 7d, then garbage-collect unused store paths.
clean:
  sudo nix profile wipe-history --profile /nix/var/nix/profiles/system --older-than 7d
  sudo nix-collect-garbage --delete-old

# Only gc (keep all generations) — frees space without losing rollbacks.
gc:
  sudo nix-collect-garbage --delete-old

# ── git ──────────────────────────────────────────────────────────
# Stage + show what's about to be committed. Rollback = `git checkout <sha> && just deploy`.
status:
  git status --short

# ── nixos-anywhere (provisioning new hosts) ─────────────────────
# Provision a fresh machine via nixos-anywhere. The target must be
# booted from a NixOS installer USB (or any Linux with kexec + SSH).
# This WIPES the target disk and installs NixOS from the flake.
# Usage: just provision hostname=homelab ip=192.168.1.50
provision hostname ip:
  nix run github:nix-community/nixos-anywhere -- \
    --flake .#{{hostname}} \
    --target-host root@{{ip}} \
    --generate-hardware-config nixos-generate-config hosts/{{hostname}}/hardware-configuration.nix

# Test a host's disk layout in a VM — no install, no disk changes.
# Boots a QEMU VM with the disko config to verify partitioning works.
# Usage: just vm-test hostname=UwU
vm-test hostname:
  nix run github:nix-community/nixos-anywhere -- \
    --flake .#{{hostname}} \
    --vm-test

# Deploy to an existing remote host (after first provisioning).
# Usage: just deploy-remote hostname=homelab ip=192.168.1.50
deploy-remote hostname ip:
  nixos-rebuild switch --flake .#{{hostname}} --target-host root@{{ip}}