# nix-config

Jaide's NixOS flake configuration, structured following [ryan4yin's NixOS & Flakes Book](https://github.com/ryan4yin/nixos-and-flakes-book).

## Structure

```
.
├── flake.nix              # Entry point — inputs, outputs, nixosConfigurations
├── flake.lock             # Pinned dependency versions (reproducibility)
├── Justfile               # Command shortcuts (`just deploy`, `just up`, etc.)
├── modules/               # Shared, host-agnostic NixOS modules
│   ├── default.nix        # Import-only — aggregates all submodules
│   ├── boot/              # systemd-boot, zram, fstrim, gc, kernel
│   ├── nix/               # Flakes, unfree, editor, nix-channel disable
│   ├── network/           # NetworkManager, IVPN (+ pinned IVPN overlay)
│   ├── firewall/          # nftables stealth firewall (default-deny incoming)
│   ├── security/          # USBGuard (USB device whitelist)
│   ├── locale/            # Timezone (Europe/Berlin), locale (en_US + de_DE)
│   ├── users/             # User account (jaide) — no home-manager
│   ├── audio/             # PipeWire + WirePlumber (device profile pinning)
│   ├── printing/          # CUPS (socket-activated, no auto-discovery)
│   ├── packages/          # Base CLI tools + opt-in subfolders
│   │   ├── packages.nix   # Universal: vim, git, ripgrep, jq, fzf, ghostty...
│   │   ├── file-manager/  # Nautilus + gvfs + udisks2
│   │   ├── media/         # mpv (with scripts), yt-dlp, ffmpeg
│   │   ├── onepassword/   # 1Password GUI + CLI + polkit
│   │   └── network-tools/ # Wireshark, nmap, tcpdump, tshark, etc.
│   ├── shell/             # Bash, git defaults, starship
│   ├── bluetooth/         # Bluez (no blueman — DMS has its own widget)
│   ├── theming/           # GTK/Qt themes, qt6ct, OZONE_WL
│   ├── fonts/             # Noto (CJK + emoji), Nerd Font, fontconfig
│   ├── firmware/          # fwupd (LVFS firmware updates)
│   ├── keyring/           # GNOME Keyring (auto-unlock via greetd PAM)
│   ├── wm/                # Shared compositor modules
│   │   ├── mango/         # MangoWM (dwl-based Wayland compositor)
│   │   └── dms/           # DankMaterialShell (bar/launcher/lock) + greeter
│   ├── ai/                # Hermes Agent + Mnemosyne memory provider
│   └── cloud/             # rclone Google Drive sync (systemd user timer)
├── overlays/
│   └── default.nix        # Exposes pkgs.betterbird, pkgs.octarine, pkgs.hytale
├── pkgs/                  # Custom packages (via callPackage)
│   ├── default.nix        # Aggregator
│   ├── betterbird/        # Thunderbird fork (pre-built binary)
│   ├── octarine/          # Markdown note-taking app (Tauri)
│   └── hytale/            # Hytale game launcher (FHS-wrapped binary)
└── hosts/                 # Per-host configuration
    ├── UwU/               # Personal laptop (AMD + NVIDIA RTX 3080)
    │   ├── default.nix    # Imports shared modules + host-specific
    │   ├── hardware-configuration.nix  # Auto-generated (sacred)
    │   ├── state.nix      # system.stateVersion
    │   ├── graphics/      # NVIDIA proprietary driver, latest kernel
    │   ├── gaming/        # Steam, Proton, Heroic, Wine, MangoHud, gamescope
    │   ├── macrotool/     # Tauri macro app runtime deps + udev rules
    │   ├── devices/       # YubiKey + Scyrox keyboard/mouse udev rules
    │   ├── packages/      # UwU-only GUI apps (Discord+Equicord, Seanime...)
    │   ├── network/       # Hostname
    │   ├── shell/         # Rebuild alias targets .#UwU, git identity
    │   └── users/         # Host-specific groups (wireshark, input, uinput)
    └── TSBW-W01800/       # Work laptop (AMD, LUKS, Thunderbolt, YubiKey)
        ├── default.nix    # Imports shared modules + host-specific
        ├── hardware-configuration.nix  # Auto-generated (sacred)
        ├── state.nix      # system.stateVersion
        ├── hardware/      # LUKS + FIDO2 unlock, Thunderbolt initrd auth, AMD graphics
        ├── security/      # YubiKey PAM (greetd, login, sudo)
        ├── boot/          # systemd initrd (for FIDO2 + Thunderbolt)
        ├── network/       # Hostname + dnsproxy (DoH + internal DNS routing)
        ├── services/      # Printing, scanning, Steam, upower, gvfs
        ├── desktop/       # mango (primary) + niri (secondary), DMS overrides
        ├── packages/      # Work tools, games, browsers, disk recovery, archives
        ├── users/         # Host-specific groups + kate
        └── shell/         # Rebuild alias targets .#TSBW-W01800, git identity
```

## Conventions

- **No home-manager** — user dotfiles stay writable. Programs that rewrite their own configs (git, bash, starship, ...) are configured at the system level via `/etc` and the user overrides per-user.
- **`default.nix` is import-only** — every module folder has a `default.nix` that only does `imports = [ ./<name>.nix ];`. All actual config lives in the sibling `<name>.nix`.
- **`lib.mkDefault` in shared modules, `lib.mkForce` in host overrides** — the base module sets a default (priority 1000), the host overrides it (priority 50). Direct assignments are priority 100 (between the two).
- **`specialArgs = { inherit inputs pkgs-stable; }`** — all flake inputs and the pre-created stable nixpkgs instance are available to every submodule.
- **`hardware-configuration.nix` is sacred** — never delete, only `mv`. Contains disk UUIDs.

## Hosts

| Host | Hardware | Compositor | Use case |
|------|----------|------------|----------|
| UwU | AMD CPU, NVIDIA RTX 3080, 32GB RAM | MangoWM | Personal — gaming, media, dev |
| TSBW-W01800 | AMD APU, 16GB RAM, LUKS + Thunderbolt dock | mango (primary) + niri (secondary) | Work — YubiKey login, printing, remote desktop |

## Usage

```bash
# Deploy to current host (auto-detected)
just deploy

# Deploy to specific host
just deploy host=UwU

# Update flake inputs
just up

# Debug deploy with full trace
just debug

# Rollback to last commit
git checkout HEAD^1 && just deploy

# Nix REPL with flake in scope
just repl
```

## USBGuard — USB Device Whitelist

USBGuard blocks unknown USB devices (BadUSB, rubber ducky, etc.) plugged in
after boot. Devices already connected when the daemon starts are trusted
automatically, so your keyboard, mouse, YubiKeys, and dock always work.

The rules are managed **declaratively** in `modules/security/security.nix`
via `services.usbguard.rules` — version-controlled and immutable at runtime.

### Adding a new device

```bash
# 1. Plug in the new device.

# 2. List blocked devices (no sudo needed — IPCAllowedUsers includes jaide)
usb-accept                 # interactive — shows blocked devices, prompts for ID
usbguard list-devices --blocked   # manual alternative

# 3. Allow it for this session (until reboot)
usb-accept <id>            # or: usbguard allow-device <id>

# 4. Get the permanent rule to paste into security.nix
usb-accept --rule <id>     # prints the rule line

# 5. Paste the rule into services.usbguard.rules in modules/security/security.nix
#    under the appropriate section, then: just deploy
```

### Quick reference

```bash
usbguard list-devices              # all devices + status
usbguard list-devices --blocked    # only blocked devices
usbguard allow-device <id>         # allow for this session
usbguard block-device <id>         # block a device
usbguard reject-device <id>        # reject (logically removes from system)
```

### How it works

| Policy | Setting | Meaning |
|--------|---------|---------|
| `presentDevicePolicy` | `allow` | Devices connected at daemon start are trusted (no lockout) |
| `presentControllerPolicy` | `keep` | USB controllers keep their current state |
| `insertedDevicePolicy` | `apply-policy` | New devices plugged in after boot are evaluated against rules |
| `implicitPolicyTarget` | `block` | Devices matching no rule are blocked |