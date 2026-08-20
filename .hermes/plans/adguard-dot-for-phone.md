# AdGuard DoT for uwu-phone over Netbird

**Goal:** Jaide's Samsung phone (uwu-phone, mesh IP `100.77.152.164`) should be able to
use `dns.jaidechan.moe` as its Android "Private DNS" provider, so all DNS goes
through AdGuard's filter lists over an encrypted, authenticated channel.

**Scope:** Luna-Server only. No changes to TSBW, UwU, or uwu-phone configs.

**Why this is small:** the wildcard cert `*.jaidechan.moe` already exists and
auto-renews. We just need to expose it on a new DoT listener (port 853) and
firewall that listener to the Netbird mesh only.

## Changes

### 1. Porkbun DNS — `dns.jaidechan.moe A 100.77.228.137`

Add an A record so `dns.jaidechan.moe` resolves to the server's mesh IP. Without
this, the phone's DoT handshake has no name → IP mapping to use.

Owned via the existing lego Porkbun DNS-01 setup. Either:
- add via Porkbun web UI (one record, instant), OR
- let lego + the existing `acme-jaidechan.moe` service handle it (no change
  needed — wildcard already covers `dns.jaidechan.moe`)

The cert is fine as-is. The A record is a Porkbun-side edit, NOT a Nix edit.

### 2. `hosts/Luna-Server/network/direct-link.nix` — AdGuard DoT + wt0:853

Inside `services.adguardhome.settings.dns`, add a `tls` block:

```nix
tls = {
  enabled = true;
  listen_port = 853;                    # standard DoT
  certificate_chain = "/var/lib/acme/jaidechan.moe/fullchain.pem";
  private_key        = "/var/lib/acme/jaidechan.moe/key.pem";
};
```

Inside `networking.firewall.interfaces.wt0` (already exists, line ~229),
add `853` to `allowedTCPPorts` (after the existing `lib.mkAfter`):
- `53` plaintext DNS (existing)
- `3000` web UI (existing)
- `853` DoT (new)

**NOT** opening 853 on `eth0` (direct-link, only UwU is on it) or `eno1`
(apartment LAN / public). The phone only reaches the server via the Netbird
mesh, so `wt0` is the only place the listener needs to be reachable.

Cert file ownership: `/var/lib/acme/jaidechan.moe/` is `acme:nginx` mode 750.
The AdGuard service needs to read those files. Two options:

- (a) add AdGuard to the `nginx` group, OR
- (b) chmod the cert dir `o+r` and trust the system.

Option (a) is the right call — it's the same pattern as nginx, and we control
group membership declaratively. Add `users.groups.acme-members = {}` and
`users.users.adguard.extraGroups = [ "acme-members" ]` (or whatever the
AdGuard NixOS module exposes — likely runs as user `adguardhome`).

### 3. Deploy

```bash
just edit adguard-dot   # snapshot + shape + dry + deploy
```

### 4. Verify

```bash
# on TSBW-W01800, which is also on the mesh (100.77.44.152):
kdig +tls @100.77.228.137 -p 853 +short jaidechan.moe
# expected: an A record, returned over TLS to dns.jaidechan.moe

# from the phone: set Private DNS to dns.jaidechan.moe
# expected: status shows "Connected" and DNS lookups resolve
```

## Risks / things that could go wrong

- **AdGuard runs as a different user than expected** and can't read the cert.
  → Fix: add it to the `nginx` group, redeploy.
- **lego rotates the cert at renewal and the AdGuard process doesn't reload.**
  → Fix: hook the renewal into a `systemd.path` that does
  `systemctl restart adguardhome`. (Can be a follow-up if it doesn't reload
  fast enough — the wildcard renews ~30 days before expiry, and the
  existing `acme-${domain}.service` already triggers a reload of the listed
  units. Add `adguardhome.service` to that list — wait, that's in
  `dashboard.nix`'s `restartUnits`, which is for the nginx renew. Need a
  SEPARATE `acme` notify unit for AdGuard. Will add as a one-liner.)
- **Wildcard cert is `*.jaidechan.moe` not `*.jaidechan.moe + jaidechan.moe`.**
  → Confirmed: existing `extraDomainNames = [ domain ];` already adds the
  bare domain. `dns.jaidechan.moe` is covered by the wildcard. ✓
