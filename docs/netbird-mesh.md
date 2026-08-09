# Private Netbird management mesh

The NixOS role in `modules/network/netbird-mesh.nix` installs Netbird
(WireGuard) and ordinary OpenSSH. Netbird SSH is deliberately not used:
OS accounts, `authorized_keys`, and Luna's account-scoped sudo policy
remain authoritative. The OpenSSH trust path is the same as it was on
the previous Tailscale mesh — only the encrypted wire underneath
changes.

## Why Netbird (instead of Tailscale)

WireGuard-based mesh VPN with an open-source coordination server. Netbird
is the encrypted wire; OpenSSH remains the trust path. The user-visible
features (MagicDNS, group-based ACL, simple peer enrollment) match
Tailscale's surface, but the coordination plane is open-source and the
NixOS module is first-class.

## Coordination server

Using hosted `netbird.io` for v1 (free tier, ≤100 peers). Self-hosting
`netbird-server` is out of scope for this migration but available as a
later move if desired.

## Access model

| Node | Group | May initiate SSH | May receive SSH |
|---|---|---:|---:|
| `UwU` | `private` | yes | yes |
| `UwU-Server` | `private` | yes | yes |
| `TSBW-W01800` | `work` | yes | yes |
| `Projet-Printserver` | `printserver` | **no** | yes |
| explicitly approved personal devices | `personal` | yes | yes |

The checked-in policy is `modules/network/netbird-policy.json`. It is
deny-by-default. The print server never appears as a `sources` clause in
any rule, and Netbird has no implicit "all members of the org" grant, so
mere mesh membership grants no management access.

## One-time Netbird setup

1. Create or open Jaide's Netbird account at [app.netbird.io](https://app.netbird.io).
2. In **Setup Keys**, create a reusable setup key named `mesh-v1` (or
   similar). Copy the key into a SOPS-encrypted file at
   `nixos-secrets/secrets/shared/netbird-setup-key.yaml` under the
   `netbird_setup_key` field. The file is rendered at
   `/run/secrets/netbird-setup-key` by sops-nix at activation time.
3. In **Policies**, create the four groups (`private`, `work`,
   `personal`, `printserver`) and import the rules from
   `modules/network/netbird-policy.json`. Save the policy.
4. Deploy the corresponding NixOS configuration to each host.
5. Enroll each host locally or through its existing trusted LAN SSH path:

   ```sh
   # The NixOS module automates enrollment via login.setupKeyFile.
   # After `nixos-rebuild switch`, the netbird-mesh systemd unit
   # registers the peer with the management server. The Netbird
   # console assigns the group based on the host's declared nodeRole.
   # Move each peer to its declared group in the console after first
   # connection if the auto-assignment is not configured.
   ```

## Migration cutover (Tailscale → Netbird)

The Tailscale mesh and the Netbird mesh are **both** wired on each host
during the cutover window — `nixos.modules.remoteMesh` (Tailscale) and
`nixos.modules.netbirdMesh` (Netbird) co-exist. The Tailscale mesh is
removed only after every reachable peer has been verified on Netbird.

The cutover is host-by-host, in this order:

1. **UwU-Server** — the bastion (hosts AdGuard, the dashboard, Gitea, etc.).
2. **UwU** — desktop client.
3. **TSBW-W01800** — work laptop, when physically at the machine.
4. **Projet-Printserver** — last, because it's the deny-by-default source.

After all four peers are verified on Netbird AND the print-server denial
invariant is confirmed via the Netbird policy tests, the Tailscale
module is removed and the host entry points drop `nixos.modules.remoteMesh`.

## Acceptance checks

From every private/work/personal node:

```sh
netbird-mesh status
netbird-mesh ping uwu-server
netbird-mesh ping uwu
netbird-mesh ping tsbw-w01800
ssh -o BatchMode=yes jaide@<destination> true
```

From the print server, connections to port 22 on private/work/personal
nodes must fail. From a private/work node, Jaide's pinned key must
reach the print server after it is deployed.

After every enrollment, record and pin the node's OpenSSH host key
before Luna performs administrative work. Netbird authenticates the
network path, but it does not replace OpenSSH host-key verification in
this design.

## Direct-link DNS split (deferred to Phase 3)

The current direct-link configuration in `hosts/UwU-Server/network/direct-link.nix`
references `tail542648.ts.net` (the Tailscale suffix) in the AdGuard
upstream-DNS split. After the Netbird mesh is verified live, this
hard-coded suffix is replaced with the Netbird magic-DNS suffix
discovered via `netbird-mesh status`. The same change applies to
`hosts/UwU/network/direct-link.nix` (the `dns-search` field) and to
`modules/ai/hermes-mobile-bridge.nix` (the QR script).

**Do not change the DNS suffix until the Netbird mesh is verified live
on the target host.** The Tailscale suffix is still authoritative
during the cutover window.

## Troubleshooting (preliminary)

- **`requested groups [...] not found`**: the Netbird policy is not
  live yet. Push the policy rules and groups first.
- **Enrollment succeeds but TCP/22 times out while `netbird-mesh ping`
  works**: similar to the Tailscale table-52 routing issue — Netbird
  uses routing tables and `wt0` may need explicit route programming.
  Restart `netbird-mesh.service` on the source node and re-check
  `ip route get <peer-100.x>`.
- **DNS for `*.netbird.cloud` does not resolve**: ensure
  `services.resolved.enable = true` is set (the module handles this).
  AdGuard upstream-DNS split must forward the Netbird domain to the
  systemd-resolved listener (configured in Phase 3).
