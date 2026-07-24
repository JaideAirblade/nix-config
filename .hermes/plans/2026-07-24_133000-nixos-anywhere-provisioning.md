# New Host Provisioning Plan (nixos-anywhere + disko)

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Enable zero-touch provisioning of new NixOS hosts from the existing flake using nixos-anywhere + disko, leveraging sops-nix for SSH key deployment so no manual `gh auth login` or key copying is needed.

**Architecture:** Add `nixos-anywhere` and `disko` as flake inputs. Create a disko disk layout module per host. New hosts boot from a NixOS installer USB (or kexec into an existing Linux install), then `nixos-anywhere` SSHes in, partitions disks via disko, installs the NixOS config from the flake, and reboots into a fully working system — SSH key from sops, all modules, everything.

**Tech Stack:** nixos-anywhere, disko, sops-nix, age, existing flake

---

## Current Context

- **UwU** and **TSBW-W01800** are manually installed NixOS hosts
- Both use `hardware-configuration.nix` with imperative disk setup (non-declarative)
- sops-nix deploys SSH keys from the private `nixos-secrets` repo
- A full config rewrite to the dendritic/flake-parts pattern is in progress (other session)
- The flake lives at `~/nixos` with `flake.nix` as entry point
- SSH keys come from sops → `/run/secrets/ssh_key` → `~/.ssh/id_ed25519` symlink
- `SOPS_AGE_KEY_FILE` points to `~/.config/sops/age/keys.txt` (3 YubiKey identities)

## Assumptions

- The config rewrite to dendritic pattern will be completed before this plan is executed
- New hosts will be x86_64 Linux machines accessible via SSH (or physical access for USB boot)
- The sops-nix module, SSH key deployment, and git config all carry over to the new structure
- The `nixos-secrets` repo and `.sops.yaml` are already set up with key rules

---

## What nixos-anywhere Does

```
┌─────────────────────────────────────────────────────────────┐
│  Your workstation (UwU)                                      │
│  ~/nixos flake                                              │
│                                                             │
│  nix run github:nix-community/nixos-anywhere \             │
│    --flake .#newhost \                                      │
│    --target-host root@192.168.1.50                          │
│                                                             │
│  1. SSH into target (running NixOS ISO or any Linux)        │
│  2. Run disko script → partition + format disks              │
│  3. Build NixOS config from flake locally                  │
│  4. Copy closure to target via nix-copy-closure             │
│  5. Activate the system                                     │
│  6. Reboot → fully working NixOS                             │
└─────────────────────────────────────────────────────────────┘
         │ SSH
         ▼
┌─────────────────────────────────────────────────────────────┐
│  Target machine (new host)                                   │
│  Booted from NixOS USB installer (or kexec from Linux)       │
│  - DHCP gets IP                                              │
│  - SSH enabled with root password or key                    │
│  - nixos-anywhere does the rest                              │
│                                                             │
│  After reboot:                                               │
│  - sops-nix deploys SSH key → ~/.ssh/id_ed25519             │
│  - git works immediately (no gh auth login)                 │
│  - All modules from the flake are active                     │
│  - pcscd running for YubiKey                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Task 1: Add flake inputs for nixos-anywhere and disko

**Objective:** Add the two new flake inputs needed for declarative provisioning.

**Files:**
- Modify: `flake.nix` (inputs section)
- Modify: `flake.lock` (auto-updated by `nix flake lock`)

**Step 1: Add inputs to flake.nix**

Add to the `inputs` attrset in `flake.nix`:

```nix
    # disko — declarative disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nixos-anywhere — zero-touch NixOS provisioning via SSH
    # Not a NixOS module — it's a CLI tool we run from the workstation.
    # Added as flake input so we can `nix run` it without installing globally.
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

**Step 2: Update flake lock**

```bash
cd ~/nixos
nix flake lock --update-input disko
nix flake lock --update-input nixos-anywhere
```

**Step 3: Verify both inputs resolve**

```bash
nix flake show .#disko 2>&1 | head -5
nix flake show .#nixos-anywhere 2>&1 | head -5
```

Expected: both show package/app outputs without errors.

**Step 4: Commit**

```bash
git add flake.nix flake.lock
git commit -m "feat: add disko + nixos-anywhere flake inputs"
```

---

## Task 2: Create a shared disko disk layout module

**Objective:** Create a reusable declarative disk layout that works for most single-disk UEFI systems.

**Files:**
- Create: `modules/disko/disko.nix`
- Create: `modules/disko/default.nix` (import-only)

**Step 1: Create the module**

`modules/disko/default.nix`:
```nix
{ ... }:
{
  imports = [ ./disko.nix ];
}
```

`modules/disko/disko.nix`:
```nix
# Declarative disk partitioning via disko.
#
# This is a TEMPLATE — each host overrides `disko.devices.disk.main.device`
# with its actual disk path (e.g. /dev/nvme0n1, /dev/sda).
#
# Layout:
#   - 1M   EFI boot partition (BIOS fallback, type EF02)
#   - 500M EFI System Partition (ESP, type EF00, FAT32, /boot)
#   - rest LUKS-encrypted btrfs root with subvolumes
#
# For hosts that don't want encryption, set:
#   disko.enableEncryption = false;
# in the host config to use plain btrfs instead.
{ lib, ... }:

{
  options.disko = {
    enableEncryption = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to encrypt the root partition with LUKS.";
    };
  };

  config = {
    # disko is imported per-host, not globally
    # The host sets disko.devices.disk.main.device = "/dev/nvme0n1";
  };
}
```

**Step 2: Create a standard single-disk layout as a disko config**

Create `modules/disko/single-disk.nix` — a reusable disko device config:

```nix
# Standard single-disk UEFI layout with optional LUKS encryption.
# Used by hosts that have a single disk. Override `main.device` per-host.
{ lib, config, ... }:

{
  disko.devices.disk.main = {
    type = "disk";
    # device = "/dev/nvme0n1";  # SET PER-HOST
    content = {
      type = "gpt";
      partitions = {
        # BIOS boot partition (1M, for GRUB fallback on non-EFI)
        boot = {
          size = "1M";
          type = "EF02";
          priority = 0;
        };
        # EFI System Partition
        ESP = {
          size = "512M";
          type = "EF00";
          priority = 1;
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        # Root — LUKS → btrfs with subvolumes
        root = {
          size = "100%";
          priority = 2;
          content = lib.mkIf config.disko.enableEncryption {
            type = "luks";
            name = "cryptroot";
            # LUKS password is set during install — nixos-anywhere prompts for it
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@" = { mountpoint = "/"; };
                "@/nix" = { mountpoint = "/nix"; };
                "@/home" = { mountpoint = "/home"; };
                "@/var" = { mountpoint = "/var"; };
                "@/snapshots" = { mountpoint = "/.snapshots"; };
              };
            };
          };
          # Plain btrfs (no encryption) when enableEncryption = false
          content = lib.mkIf (!config.disko.enableEncryption) {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes = {
              "@" = { mountpoint = "/"; };
              "@/nix" = { mountpoint = "/nix"; };
              "@/home" = { mountpoint = "/home"; };
              "@/var" = { mountpoint = "/var"; };
              "@/snapshots" = { mountpoint = "/.snapshots"; };
            };
          };
        };
      };
    };
  };
}
```

**Step 3: Wire into modules tree**

Add `./disko` to `modules/default.nix` imports (or in the dendritic rewrite, it auto-imports).

**Step 4: Verify it evaluates**

```bash
nixos-rebuild dry-build --flake .#UwU
```

Expected: compiles (disko module is loaded but doesn't do anything until a host sets `disko.devices.disk.main.device`).

**Step 5: Commit**

```bash
git add modules/disko/
git commit -m "feat: add disko single-disk layout module with optional LUKS"
```

---

## Task 3: Add disko module to flake outputs

**Objective:** Make the disko module importable by hosts and expose diskoConfigurations for nixos-anywhere.

**Files:**
- Modify: `flake.nix` (outputs section)

**Step 1: Add disko module to nixosSystem modules**

In each host's `modules` list in `flake.nix`, add:

```nix
  inputs.disko.nixosModules.disko
```

So a host definition looks like:

```nix
  newhost = nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit inputs pkgs-stable; };
    modules = [
      { nixpkgs.overlays = [ inputs.self.overlays.additions ]; }
      inputs.disko.nixosModules.disko
      ./hosts/newhost
      ...
    ];
  };
```

**Step 2: Verify**

```bash
nixos-rebuild dry-build --flake .#UwU
```

Expected: still compiles.

**Step 3: Commit**

```bash
git add flake.nix
git commit -m "feat: wire disko module into nixosSystem"
```

---

## Task 4: Create a new host directory template

**Objective:** Document the exact steps to add a new host to the flake.

**Files:**
- Create: `hosts/<newhost>/default.nix`
- Create: `hosts/<newhost>/hardware-configuration.nix` (generated by nixos-anywhere)
- Create: `hosts/<newhost>/disk-layout.nix` (disko device config)
- Modify: `flake.nix` (add nixosConfigurations entry)

**Step 1: Create host directory**

```bash
mkdir -p hosts/<newhost>/{network,shell,users,packages}
```

**Step 2: Create host entry**

`hosts/<newhost>/default.nix`:

```nix
# New host entry.
# Imports shared module tree + host-specific modules.
{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-layout.nix
    ../../modules

    # Host-specific modules
    ./network
    ./shell
    ./users
    ./packages
  ];
}
```

**Step 3: Create disk layout**

`hosts/<newhost>/disk-layout.nix`:

```nix
# Declarative disk layout for this host.
# The device path must match the actual disk on the target machine.
# Check with `lsblk` on the target before deploying.
{ ... }:

{
  # Import the shared single-disk layout
  imports = [ ../../modules/disko/single-disk.nix ];

  # Set the actual disk device for this host
  disko.devices.disk.main.device = "/dev/nvme0n1";  # CHANGE THIS

  # For non-encrypted hosts:
  # disko.enableEncryption = false;
}
```

**Step 4: Add to flake.nix**

```nix
  <newhost> = nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit inputs pkgs-stable; };
    modules = [
      { nixpkgs.overlays = [ inputs.self.overlays.additions ]; }
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      ./hosts/<newhost>
    ];
  };
```

**Step 5: Verify it evaluates**

```bash
nixos-rebuild dry-build --flake .#<newhost>
```

**Step 6: Commit**

```bash
git add hosts/<newhost>/ flake.nix
git commit -m "feat: add <newhost> host entry with disko layout"
```

---

## Task 5: Add the new host's age key to sops

**Objective:** After the first deploy, add the new host's age key to `.sops.yaml` so it can decrypt secrets.

**Files:**
- Modify: `~/nixos-secrets/.sops.yaml`

**Step 1: Deploy to generate the host key**

After nixos-anywhere installs and reboots the host:

```bash
ssh root@<newhost-ip>
sudo age-keygen -y /var/lib/sops-nix/key.txt
```

Copy the `age1...` output.

**Step 2: Add to .sops.yaml**

Edit `~/nixos-secrets/.sops.yaml`:

```yaml
keys:
  - &host_<newhost> age1xxxxx...  # paste from step 1
```

Add `*host_<newhost>` to the relevant `creation_rules` key_groups.

**Step 3: Re-encrypt secrets**

```bash
cd ~/nixos-secrets
sops updatekeys secrets.yaml
# (touch YubiKey when prompted)
git add -A && git commit -m "add <newhost> host key" && git push
```

**Step 4: Update flake lock**

```bash
cd ~/nixos
nix flake lock --update-input nixos-secrets
```

**Step 5: Rebuild the new host**

```bash
nixos-rebuild switch --flake .#<newhost> --target-host root@<newhost-ip>
```

After this, the new host can decrypt `secrets.yaml` and the SSH key gets deployed automatically.

**Step 6: Commit**

```bash
git add flake.lock
git commit -m "feat: add <newhost> sops key, update nixos-secrets"
```

---

## Task 6: Add nixos-anywhere deploy command to Justfile

**Objective:** Add convenient Justfile targets for provisioning new hosts.

**Files:**
- Modify: `~/nixos/Justfile`

**Step 1: Add deploy targets**

```makefile
# Provision a new host via nixos-anywhere
# Usage: just provision <hostname> <ip>
# Example: just provision homelab 192.168.1.50
provision hostname ip:
    nix run github:nix-community/nixos-anywhere -- \
      --flake .#{{hostname}} \
      --target-host root@{{ip}} \
      --generate-hardware-config nixos-generate-config hosts/{{hostname}}/hardware-configuration.nix

# Deploy to an existing remote host (after first provisioning)
# Usage: just deploy-remote <hostname> <ip>
deploy-remote hostname ip:
    sudo nixos-rebuild switch --flake .#{{hostname}} --target-host root@{{ip}}

# Test a host's disk layout in a VM (no install)
# Usage: just vm-test <hostname>
vm-test hostname:
    nix run github:nix-community/nixos-anywhere -- \
      --flake .#{{hostname}} \
      --vm-test
```

**Step 2: Verify Justfile parses**

```bash
just --list
```

**Step 3: Commit**

```bash
git add Justfile
git commit -m "feat: add nixos-anywhere provision + deploy-remote Justfile targets"
```

---

## Full provisioning workflow (cheat sheet)

After all tasks are done, provisioning a new host is:

```bash
# 1. Boot the target from NixOS USB installer (or any Linux with kexec)
# 2. Set a root password on the target (if using password auth):
#    ssh root@<ip>   # or use the NixOS installer's root password
# 3. From your workstation:
cd ~/nixos
just provision <hostname> <ip>

# 4. Wait for install + reboot
# 5. SSH in (SSH key from sops is already deployed):
ssh jaide@<ip>

# 6. Add the new host's age key to sops:
ssh root@<ip> "age-keygen -y /var/lib/sops-nix/key.txt"
# → paste into ~/nixos-secrets/.sops.yaml, sops updatekeys, push

# 7. Update flake lock + rebuild:
nix flake lock --update-input nixos-secrets
just deploy-remote <hostname> <ip>
```

That's it. No `gh auth login`, no manual SSH key copy, no manual partitioning.

---

## Risks and Tradeoffs

1. **disko replaces hardware-configuration.nix** — existing hosts (UwU, TSBW-W01800) still use imperative `hardware-configuration.nix`. We don't need to convert them. Only new hosts use disko.

2. **LUKS password** — nixos-anywhere prompts for the LUKS password during install. This password is NOT stored in the flake (it's in the LUKS header on disk). If you forget it, the disk is unrecoverable. Consider storing it in sops or 1Password.

3. **Build time** — nixos-anywhere builds the full system closure locally, then copies it to the target. For a full desktop config, this can take a while. Use `--build-on-remote` if the target is powerful enough.

4. **btrfs subvolumes** — the layout uses btrfs subvolumes for `/`, `/nix`, `/home`, `/var`, `/.snapshots`. The `/.snapshots` subvolume is for future snapshot-based rollback (snapper/btrbk) but isn't configured yet.

5. **Migrating existing hosts** — possible but risky. disko will **destroy all data** on the target disk. Only do this for fresh installs or when you have backups.

6. **Config rewrite dependency** — this plan assumes the dendritic rewrite is done. The `modules/default.nix` imports and `flake.nix` structure may differ in the new pattern. Adapt accordingly.

---

## Open Questions

- Do you want btrfs compression (zstd) on the root subvolumes? Easy to add: `content.extraArgs = [ "-f" ]` → add `"--compress=zstd"` to mount options.
- Do you want a swap partition or swap file? disko can create a swap partition, or use zram (already on TSBW-W01800).
- Do you want separate disko layouts for different disk types (NVMe vs SATA vs RAID)? The template handles single-disk; multi-disk/RAID needs a custom layout.
- Should the LUKS password be stored in sops for recovery? Risk: if the sops repo is compromised, the disk encryption key is exposed. Better to keep it in 1Password.