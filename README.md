# nix-config

Jaide's multi-host NixOS flake, structured around the current
[Dendritic Pattern](https://github.com/mightyiam/dendritic).

## Architecture

`flake.nix` recursively imports every Nix feature below `modules/` and
`hosts/`. Each feature is a top-level flake-parts module that contributes to a
merged lower-level module:

- `nixos.modules.common` — shared system and desktop configuration.
- `nixos.modules.fileManager`, `personal`, `virtualisation`, `adLab`, `disk`
  — opt-in roles selected by a host entry point.
- `nixos.modules.remoteAccess` — fail-closed AWG/SSH role; not selected until
  per-host keys, reachable endpoints, and FIDO2 authorized keys exist.
- `nixos.hosts.<name>` — all feature contributions specific to one machine.

The storage options in `modules/options.nix` use `deferredModule`, so separate
top-level files merge naturally. Feature files capture flake inputs lexically;
the NixOS evaluations do not receive `specialArgs` or the complete input set.

Intentional lower-level exceptions are excluded from recursive importing:

- host `default.nix` entry points;
- generated `hardware-configuration.nix` files;
- `callPackage` expressions under `pkgs/`;
- overlay expressions under `overlays/` and `*.overlay.nix` helpers.

## Hosts

| Host | Hardware | Roles | Use case |
|------|----------|-------|----------|
| UwU | AMD CPU, NVIDIA RTX 3080, 32GB RAM | common, personal, disk, virtualisation | Personal desktop — gaming, media, development |
| TSBW-W01800 | AMD APU, LUKS, Thunderbolt dock | common | Work laptop — YubiKey login, printing, recovery tools |
| OwO-Family | Family desktop | common, file manager, virtualisation | Preserved but not exported; provisioning waits for a verified disk by-id |

## Safety and permissions

- User-owned dotfiles remain writable; there is no home-manager deployment.
- `jaide` is never added to the `root` group. Network diagnostics use a
  dedicated `net-report` group and group-restricted capability wrappers.
- The NixOS nftables firewall remains enabled so service `openFirewall`
  declarations and interface-specific rules compose correctly.
- Remote access is disabled until complete cryptographic and reachability
  settings are available. The role asserts per-host keys, bootstrap endpoints,
  and non-empty SSH authorized keys when enabled.
- Destructive Disko layouts use verified `/dev/disk/by-id/...` paths only.

## Usage

```bash
# Run formatter, static analysis, ShellCheck, and host evaluations
nix flake check

# Check review regressions explicitly
tests/review-regressions.sh

# Deploy to the current host, or select a host explicitly
just deploy
just deploy host=UwU

# Update pinned inputs
just up

# Evaluate with a full trace
just debug
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