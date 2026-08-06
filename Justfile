# Justfile — shortcuts for the NixOS flake at ~/nixos.
# Run `just` with no args to list recipes. `just <recipe>` runs one.
#
# Host is auto-detected from the system hostname, so `just deploy` works
# on any machine in the flake without specifying the target. Override with a
# positional argument, for example `just deploy TSBW-W01800`.
#
# IMPORTANT (2026-08-06): every local deploy recipe calls
# scripts/confirm-local-deploy.sh, which (1) prints a loud warning if the
# target host arg does NOT match the local hostname, and (2) requires an
# explicit "YES" typed at a real terminal before proceeding. This guard
# exists because `just deploy` is a LOCAL deploy — running it on the wrong
# machine applies that machine's config here, not remotely. Use
# `just deploy-remote <host> <ip>` to push a config to a different machine.
host := `hostname`

# ── deploy / build ──────────────────────────────────────────────
# Deploy the current host (auto-detected). Override: `just deploy TSBW-W01800`.
# Guarded by scripts/confirm-local-deploy.sh — requires "YES" at a tty and
# warns loudly if target != hostname.
deploy $host=host:
    ./scripts/confirm-local-deploy.sh "$host"
    nixos-rebuild switch --flake ".#$host" --elevate=sudo

# Build the full system closure without activating — safest pre-check.
# Non-activating, so no confirm gate needed.
dry $host=host:
    nixos-rebuild dry-build --flake ".#$host"

# Build a throwaway VM from the config (no host changes). Result link: ./result
vm $host=host:
    nixos-rebuild build-vm --flake ".#$host"

# Verbose deploy with full trace + build logs (for debugging eval errors).
# Guarded the same way as `deploy`.
debug $host=host:
    ./scripts/confirm-local-deploy.sh "$host"
    nixos-rebuild switch --flake ".#$host" --elevate=sudo --show-trace --print-build-logs --verbose

# ── flake inputs ──────────────────────────────────────────────────
# Update all flake inputs, then deploy the current host.
# Guarded the same way as `deploy`.
up $host=host:
    ./scripts/confirm-local-deploy.sh "$host"
    nix flake update
    nixos-rebuild switch --flake ".#$host" --elevate=sudo

# Update one required input, then deploy. Usage: `just upp hermes-agent UwU`
# Guarded the same way as `deploy`.
upp $i $host=host:
    ./scripts/confirm-local-deploy.sh "$host"
    nix flake update "$i"
    nixos-rebuild switch --flake ".#$host" --elevate=sudo

# Show what changed in flake.lock vs the last commit.
diff:
    git diff flake.lock

# ── inspection / debugging ─────────────────────────────────────
# Nix REPL loaded with this flake in scope.
repl:
    nix repl .

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
    sudo nix-collect-garbage

# Only gc (keep all generations) — frees space without losing rollbacks.
gc:
    sudo nix-collect-garbage

# ── git ──────────────────────────────────────────────────────────
# Show uncommitted changes. Rollback = `git checkout <sha> && just deploy`.
status:
    git status --short

# ── nixos-anywhere (provisioning new hosts) ─────────────────────
# Safely provision a fresh machine. The script verifies the remote disk,
# prepares and tests the host's sops key before installation, pauses to prove
# the EFI boot path, and only then reboots. This WIPES the confirmed target.
# Usage: just provision UwU-Server 192.168.1.50
[arg('hostname', pattern='[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?')]
[arg('ip', pattern='[A-Za-z0-9][A-Za-z0-9.:-]*')]
provision $hostname $ip:
    ./scripts/bootstrap-host.sh "$hostname" "$ip"

# Backward-compatible name for the same guarded provisioning workflow.
[arg('hostname', pattern='[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?')]
[arg('ip', pattern='[A-Za-z0-9][A-Za-z0-9.:-]*')]
bootstrap $hostname $ip:
    ./scripts/bootstrap-host.sh "$hostname" "$ip"

# Test a host's disk layout in a VM — no install, no disk changes.
# Boots a QEMU VM with the disko config to verify partitioning works.
# Usage: just vm-test UwU
vm-test $hostname:
    nix run .#nixos-anywhere -- \
      --flake ".#$hostname" \
      --vm-test

# Deploy to an existing remote host (after first provisioning).
# Builds the closure LOCALLY (fast, uses this machine's CPU + nix store),
# copies the store paths to the target, and activates remotely via
# jaide@ + sudo. No root SSH access needed (PermitRootLogin=no is fine).
# Usage: just deploy-remote UwU-Server 192.168.1.50
deploy-remote $hostname $ip:
    nixos-rebuild switch \
      --flake ".#$hostname" \
      --target-host "jaide@$ip" \
      --use-remote-sudo \
      --use-substitutes

# Build a remote host's closure locally without activating — dry-run
# pre-check. Same local-build strategy as deploy-remote.
# Usage: just dry-remote UwU-Server 192.168.1.50
dry-remote $hostname $ip:
    nixos-rebuild dry-activate \
      --flake ".#$hostname" \
      --target-host "jaide@$ip" \
      --use-remote-sudo \
      --use-substitutes

# ── AD test lab ─────────────────────────────────────────────────
# Start the AD lab network + domain controller VM
lab-up:
    lab-net-create
    virsh start ad-dc1 2>/dev/null || echo "DC not defined yet — create with: just lab-create-dc"

# Stop the entire lab (network + all VMs)
lab-down:
    -for vm in $(virsh list --name --state-running 2>/dev/null | grep '^ad-'); do virsh shutdown $$vm; done
    sleep 3
    -for vm in $(virsh list --name --all 2>/dev/null | grep '^ad-'); do virsh destroy $$vm 2>/dev/null || true; done
    lab-net-destroy

# Lab status — network + VMs + SSH keys
lab-status:
    lab-status

# Create the domain controller VM from ISO (one-time setup)
lab-create-dc $iso="":
    lab-create-dc "$iso"

# Create the client base image from ISO (one-time setup)
lab-create-client-base $iso="":
    lab-create-client-base "$iso"

# Create the NixOS print server VM in the ad-lab network
lab-create-printserver:
    lab-create-printserver

# Create a fresh client VM from base image (throws away old one)
# Generates temp SSH key, injects into VM, adds SSH config entry
lab-fresh-client $name="ad-client1":
    lab-fresh-client "$name"

# Revert a client VM to its base snapshot (faster than fresh clone)
lab-revert $name="ad-client1":
    lab-revert "$name"

# Nuke a client VM + delete its SSH keys
lab-nuke $name="ad-client1":
    lab-nuke "$name"

# Attach a direct macvtap NIC (explicit physical interface required).
lab-bridge $name $iface:
    lab-bridge-attach "$name" "$iface"

# ── TSBW Windows VM (real AD domain join) ──────────────────────
# Create the Windows VM bridged to the Thunderbolt dock NIC (enp1s0)
# Pass the Windows ISO path: just tsbw-vm-create ~/Downloads/Win11.iso
tsbw-vm-create $iso="":
    tsbw-vm-create "$iso"

# Start the TSBW Windows VM
tsbw-vm-start:
    tsbw-vm-start

# Stop the TSBW Windows VM (graceful shutdown)
tsbw-vm-stop:
    tsbw-vm-stop

# Bridge the VM to the physical NIC (enp1s0 by default)
tsbw-vm-bridge $iface="enp1s0":
    tsbw-vm-bridge "$iface"

# TSBW Windows VM status — VM, network, noVNC URL
tsbw-vm-status:
    tsbw-vm-status

# Destroy the TSBW Windows VM + delete its disk
tsbw-vm-nuke:
    tsbw-vm-nuke
