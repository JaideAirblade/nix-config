# Private Tailscale management mesh

The NixOS role in `modules/network/tailscale-mesh.nix` installs Tailscale and
ordinary OpenSSH. Tailscale SSH is deliberately not used: OS accounts,
`authorized_keys`, and Luna's account-scoped sudo policy remain authoritative.

## Access model

| Node | Tag | May initiate SSH | May receive SSH |
|---|---|---:|---:|
| `UwU` | `tag:private` | yes | yes |
| `Luna-Server` | `tag:private` | yes | yes |
| `TSBW-W01800` | `tag:work` | yes | yes |
| explicitly approved personal devices | `tag:personal` | yes | yes |
| `Projet-Printserver` | `tag:printserver` | **no** | yes |

The checked-in policy is `modules/network/tailscale-policy.json`. It is
deny-by-default. The print server never appears as an ACL source, and policy
tests explicitly deny it access to private, work, and personal nodes. There is
no `autogroup:member` rule: mere tailnet membership grants no management access.

## One-time tailnet setup

1. Create or open Jaide's Tailscale tailnet.
2. In **Access controls**, replace the policy with
   `modules/network/tailscale-policy.json` and save it. Tailscale must report
   that all embedded policy tests pass.
3. Deploy the corresponding NixOS configuration to each host.
4. Enroll each host locally or through its existing trusted LAN SSH path:

   ```sh
   # UwU
   sudo tailscale up --hostname=UwU --advertise-tags=tag:private

   # Luna-Server
   sudo tailscale up --hostname=Luna-Server --advertise-tags=tag:private

   # Work laptop; run once locally after its rebuild
   sudo tailscale up --hostname=TSBW-W01800 --advertise-tags=tag:work

   # Other explicitly approved personal device with a Tailscale CLI
   sudo tailscale up --advertise-tags=tag:personal

   # Only after the print server is deployed
   sudo tailscale up --hostname=Projet-Printserver --advertise-tags=tag:printserver
   ```

   Open the authentication URL printed by each command. Do not paste an auth
   key into the shell history or repository.

## Existing Luna account migration

UwU and Luna-Server were originally deployed with Luna's home at
`/var/lib/luna`. Do not move that directory during Nix activation.

Before switching each existing host, create and verify the rollback backup:

```sh
sudo install -d -m 0700 /var/backups
sudo tar --acls --xattrs -cpf \
  /var/backups/luna-home-before-standard-home.tar \
  -C /var/lib luna
sudo chmod 0600 /var/backups/luna-home-before-standard-home.tar
sudo test -s /var/backups/luna-home-before-standard-home.tar
```

Switch the new generation. Verify `getent passwd luna` now names
`/home/luna`, then copy and verify the old contents with the packaged helper:

```sh
sudo migrate-luna-home
getent passwd luna
sudo stat -c '%n %a %U:%G' /home/luna /var/lib/luna \
  /var/backups/luna-home-before-standard-home.tar
```

The helper uses `rsync -aHAX`, performs a checksum dry-run, and deliberately
retains `/var/lib/luna`. Remove the legacy directory only after fresh Luna
logins and administrative commands have passed and the rollback window closes.

## Acceptance checks

From every private/work/personal node:

```sh
tailscale status
tailscale ping UwU
tailscale ping Luna-Server
tailscale ping TSBW-W01800
ssh -o BatchMode=yes <authorized-user>@<destination> true
```

From the print server, connections to port 22 on private/work nodes must fail.
From a private/work node, Jaide's pinned key must reach the print server after
it is deployed. Luna's distinct Luna-Server fleet key is deployed only on
Luna-Server and is authorized only where `automationAccounts` is selected.

After every enrollment, record and pin the node's OpenSSH host key before Luna
performs administrative work. Tailscale authenticates the network path, but it
does not replace OpenSSH host-key verification in this design.

## Troubleshooting (learned 2026-08-05)

- **`requested tags [...] are invalid or not permitted`**: the tailnet policy
  is not live yet. Push `tailscale-policy.json` first. The admin console's
  visual rule builder cannot import a policy file; use the API instead:
  `curl -X POST https://api.tailscale.com/api/v2/tailnet/-/acl
  -H "Authorization: Bearer <api-token>" -H "Content-Type: application/hujson"
  --data-binary @modules/network/tailscale-policy.json` (PUT returns 405 on the
  current API; validate first with POST to `/acl/validate`).
- **Enrollment succeeds but TCP/22 times out while `tailscale ping` works**:
  check `ip route get <peer-100.x>` on the source node. If it resolves via the
  LAN default route instead of `tailscale0`, tailscaled started before its
  first netmap and never programmed the per-peer table-52 routes. Restart
  `tailscaled.service` on the source node and re-check the route. Ping uses
  TSMP inside tailscaled, so it works even when no host routes exist.
