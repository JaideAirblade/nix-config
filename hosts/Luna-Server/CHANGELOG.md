# Luna-Server Changelog

Revertible record of host-specific changes. Each entry lists the exact
files touched so a revert is `git revert <commit>` or the documented
rollback step.

---

## 2026-08-19 — RENAMED: UwU-Server → Luna-Server

**Commit:** `baf6811` (config) + nixos-secrets `9adc2d4` (secrets repo, moved first)

**Files changed:** `hosts/UwU-Server/` → `hosts/Luna-Server/` (whole tree),
flake attr `nixosConfigurations.Luna-Server`, `networking.hostName`,
sops paths `secrets/Luna-Server/*`, ssh alias `luna-server`, fleet deploy
tables (`pkgs/.update-config.json`), all referencing tests/scripts/docs.

**Why:** Jaide's call — "since you always confuse uwu-server with uwu in
everything". The server is now named after Luna.

**Rollback:** `git revert baf6811` + revert nixos-secrets `9adc2d4` +
re-run `nix flake lock --update-input nixos-secrets` + redeploy. Hostname
flips back on activation.

**Unchanged:** netbird IP 100.77.228.137, `*.jaidechan.moe` domains,
NM profile "Direct Link (UwU-Server)" on UwU (label matched by the
failover script — do not rename casually), AdGuard/nginx/chrony data.

---

## 2026-08-14 — WiFi: disable iwlwifi BT coexistence (`bt_coex_active=0`)

**Commit:** see `git log --oneline` (message: `fix(Luna-Server): iwlwifi bt_coex_active=0 — stop BT stealing WiFi antenna time`)

**Files changed:**
- `hosts/Luna-Server/network/network.nix` — added `boot.extraModprobeConfig = 'options iwlwifi bt_coex_active=0'`

**Why:** AX200 WiFi RX collapses under load (6.5–57 Mbit/s NSS 1, TX
fine at 520 Mbit/s NSS 2), chain 1 reads ~10 dB below chain 0, 6% packet
loss + 100–400 ms spikes to gateway. BT radio idle/down the whole time —
the *firmware's* BT-coex machinery was reserving antenna time anyway.
Bluetooth itself stays enabled (bluez untouched), per Jaide 2026-08-14.

**Already live from earlier fixes (context, not part of this change):**
`iommu=pt`, `cfg80211.ieee80211_regdom=DE`, hci0 rfkill-blocked at runtime.

**Activation:** requires reboot — the module param is read-only at
runtime and reloading iwlwifi live re-triggers the AX200
"session protection" association bug.

**Rollback:** delete the `boot.extraModprobeConfig` block from
`network.nix` (or `git revert` the commit) + reboot.

**Deployed 2026-08-14** from a clean worktree (staged tree + this commit,
system `7qganf2j...`). Deployment also required:
- `overlays/python-package-fixes.nix` — mat2 override extended with
  `doInstallCheck = false` (pytest-check-hook runs in pytestCheckPhase
  after installCheckPhase; `doCheck=false` alone doesn't stop it).
  Note: the real reason the override wasn't applying was that Luna-Server's
  `default.nix` never wired the `python-package-fixes` overlay — the
  wiring is part of the staged (deployed-but-uncommitted) tree.
- Physical (user-performed, NOT config): aluminium NVMe dock that sat
  directly below the two antennas was removed 2026-08-14. Measured effect
  before reboot: 6% loss / avg 59 ms / max 397 ms → 0% loss / avg 8.9 ms /
  max 54 ms to gateway.

**Verify after reboot:**
```
cat /sys/module/iwlwifi/parameters/bt_coex_active   # must print N
iw dev wlp194s0 station dump | grep -E 'signal|bitrate'  # chain gap < 6 dB, RX NSS 2 under load
ping -c 300 -i 0.2 -q 192.168.188.1                  # loss ~0%, max < 20 ms
```
