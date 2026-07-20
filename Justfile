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