# UwU-Server Changelog

Revertible record of host-specific changes. Each entry lists the exact
files touched so a revert is `git revert <commit>` or the documented
rollback step.

---

## 2026-08-14 — WiFi: disable iwlwifi BT coexistence (`bt_coex_active=0`)

**Commit:** see `git log --oneline` (message: `fix(UwU-Server): iwlwifi bt_coex_active=0 — stop BT stealing WiFi antenna time`)

**Files changed:**
- `hosts/UwU-Server/network/network.nix` — added `boot.extraModprobeConfig = 'options iwlwifi bt_coex_active=0'`

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

**Verify after reboot:**
```
cat /sys/module/iwlwifi/parameters/bt_coex_active   # must print N
iw dev wlp194s0 station dump | grep -E 'signal|bitrate'  # chain gap < 6 dB, RX NSS 2 under load
ping -c 300 -i 0.2 -q 192.168.188.1                  # loss ~0%, max < 20 ms
```
