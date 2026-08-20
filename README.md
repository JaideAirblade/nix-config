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
| Luna-Server | Ryzen AI 9 HX 470, Radeon 890M, 64GB RAM | common, file manager, disk, gaming, SSH | Headless-capable server/desktop provisioned with Disko |
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
installation, then streamed over the authenticated installer SSH session into
`/mnt/var/lib/sops-nix/key.txt` before the first activation. The authenticated
installer SSH host keys are preserved in the mounted target at the same time.

Before running it:

1. Add and review `hosts/<host>/default.nix`, `hardware-configuration.nix`,
   `disk-layout.nix`, networking, user, and SSH modules. The Disko device must
   be the verified whole-disk `/dev/disk/by-id/...` path. Do not use `/dev/sdX`
   or `/dev/nvmeXnY` names.
2. Give a fresh account an authorized SSH key. Private devices consume the
   shared Jaide yescrypt hash from `secrets/private/accounts.yaml` through
   `sops.secrets.jaide_password_hash.neededForUsers` and
   `users.users.jaide.hashedPasswordFile`. Create or rotate it with
   `scripts/set-private-password-hash.sh`; the GUI prompt hashes the password
   in memory and writes only SOPS ciphertext. Private hosts set
   `users.mutableUsers = false`, so local `passwd` changes are replaced on the
   next activation; rotate the shared password through this helper instead.
   Commit and push the secrets repo, then update the `nixos-secrets` lock before
   provisioning. Remote
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
   and read the installer's ED25519 SHA-256 SSH fingerprint from its local
   console. Then start provisioning and enter that exact fingerprint when
   prompted:

   ```bash
   just provision <host> <installer-ip>
   ```

For unattended use, set `INSTALLER_HOST_FINGERPRINT=SHA256:...` from an
out-of-band source or provide `INSTALLER_KNOWN_HOSTS_FILE=/secure/known_hosts`.
The script will not send an installer password before that trust check passes.

The script authenticates the installer SSH key, prints the remote disk model
and serial, proves writable UEFI variables are available, and requires the exact
phrase `WIPE <by-id-path> ON <target>` before it changes anything. It masks
installer suspend, updates and verifies only the SOPS files the host needs, uses
nixos-anywhere for kexec and Disko, then performs the actual installation on the
target with `nixos-install --flake`. Before reboot it proves that `/mnt/boot` is
the vfat ESP on the configured disk, the selected loader entry's kernel/initrd
byte-match the exact store artifacts named by the installed profile's
`boot.json`, its `init=` names that same generation, and the exact
PARTUUID+systemd-boot NVRAM entry is first after re-reading `efibootmgr`. After
reboot it scans the directly connected CIDR and accepts only a candidate whose
SSH key exactly matches the protected installation identity; Ethernet MAC
randomization and a changed DHCP address therefore do not break discovery. Secret
update, decryption, Git push, password-hash activation, boot-path, SSH, and
post-boot system-state failures are fatal rather than warnings.

The controller builds the target toplevel before destructive work and, after the
authenticated kexec/Disko phases, automatically copies that closure to the
installer with `nix copy --no-check-sigs --to ssh-ng://root@...` over the pinned
root SSH channel. Signature checking is disabled only for this authenticated
transfer because locally built derivations do not carry binary-cache signatures.
The final target-side `nixos-install` remains authoritative, evaluates the
transferred reviewed source, and reuses every identical store path already
copied instead of downloading or rebuilding it. This keeps physical installs
fast and shortens the credential-bearing rescue window on VPS deployments.
Directly connected targets retain MAC-independent CIDR rediscovery after reboot;
routed VPS targets retry only their original pinned address and never trigger a
LAN scan. A shared Attic/Cachix cache remains the scalable fleet equivalent for
paths the controller does not already have.

If the host recipient already exists, implicit key rotation is refused. Supply
its matching private key explicitly:

```bash
HOST_AGE_KEY_FILE=/secure/path/<host>-age.key \
  just provision <host> <installer-ip>
```

After success, the SOPS-managed password hash is active; verify remote sudo and
review the reported `flake.lock` change before committing it. Never reboot a
remote-only machine manually when the script has paused on a boot-path
verification error; fix and re-run the verification while installer SSH access
still exists.

### Luna automation trust boundary

The dedicated Luna SSH key is intentionally a **root-equivalent fleet
credential** on private hosts. The authorized-key `restrict` option disables
forwarding, agent use, X11, and PTY allocation; it does not limit remote command
execution. Luna also has an account-scoped `NOPASSWD: ALL` rule so general
noninteractive automation can elevate with `sudo -n`.

Only `UwU` receives the SOPS-encrypted private half, owned by `jaide` with mode
`0600`. Compromise of Jaide's session or that key on `UwU` therefore grants root
automation access to every private host authorizing it. Keep it off other
machines, do not agent-forward it, and rotate/remove the dedicated public key on
all targets if the controller or ciphertext is suspected compromised. Jaide's
own sudo policy remains password-required and independent of Luna.

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