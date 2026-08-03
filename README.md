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
| UwU-Server | Ryzen AI 9 HX 470, Radeon 890M, 64GB RAM | common, file manager, disk, gaming, SSH | Headless-capable server/desktop provisioned with Disko |
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

# Deploy to the current host, or select a host explicitly (positional)
just deploy
just deploy UwU

# Update pinned inputs
just up

# Evaluate with a full trace
just debug
```

## Provisioning a new device

The guarded path is `just provision <host> <installer-ip>` (the older
`just bootstrap` name is an alias). It follows the current
[nixos-anywhere secrets workflow](https://nix-community.github.io/nixos-anywhere/howtos/secrets.html):
the machine-specific age key is generated and added as a SOPS recipient before
installation, then copied into the new root with `--extra-files`.

Before running it:

1. Add and review `hosts/<host>/default.nix`, `hardware-configuration.nix`,
   `disk-layout.nix`, networking, user, and SSH modules. The Disko device must
   be the verified whole-disk `/dev/disk/by-id/...` path. Do not use `/dev/sdX`
   or `/dev/nvmeXnY` names.
2. Give a fresh account an authorized SSH key. The provisioning script pauses
   before reboot and runs `passwd jaide` interactively inside `/mnt`, so the
   password never enters Git or the Nix store. Remote
   `nixos-rebuild --target-host jaide@...` also requires `jaide` in
   `nix.settings.trusted-users`.
3. Register every new file with Git before evaluating it; flakes ignore
   untracked files. `git add -N <file>` can expose a module path for early
   review, but stage the real content with `git add <file>` before checks that
   read it through `${self}` (inspect `git diff --cached` before committing).
4. Run the non-destructive checks:

   ```bash
   nix eval .#nixosConfigurations.<host>.config.networking.hostName --raw
   nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath
   just vm-test <host>
   nix flake check
   ```

5. Boot the target from a **wired** NixOS installer, verify backups, inspect
   `lsblk -d -o NAME,SIZE,MODEL,SERIAL` and `/dev/disk/by-id/` on the target,
   then start provisioning:

   ```bash
   just provision <host> <installer-ip>
   ```

The script fingerprints the installer SSH key, prints the remote disk model and
serial, and requires the exact phrase `WIPE <by-id-path> ON <target>` before it
changes anything. It masks installer suspend, updates and verifies only the SOPS
files the host needs, installs without rebooting, proves the systemd-boot files
and EFI NVRAM entry point to the real ESP, and only then reboots. Secret update,
decryption, Git push, boot-path, SSH, and post-boot system-state failures are
fatal rather than warnings.

If the host recipient already exists, implicit key rotation is refused. Supply
its matching private key explicitly:

```bash
HOST_AGE_KEY_FILE=/secure/path/<host>-age.key \
  just provision <host> <installer-ip>
```

After success, the password entered before reboot is active; verify remote sudo
and review the reported `flake.lock` change before committing it. Never reboot a
remote-only machine manually when the script has paused on a boot-path verification error;
fix and re-run the verification while installer SSH access still exists.

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