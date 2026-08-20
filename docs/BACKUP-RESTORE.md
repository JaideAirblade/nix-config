# Backup & restore

UwU-Server uses [restic][restic] for off-site backups to a private
[Backblaze B2][b2] bucket. Backups are declarative NixOS config
(`hosts/UwU-Server/server/backups.nix`); restoring is a shell exercise.

[restic]: https://restic.net/
[b2]: https://www.backblaze.com/cloud-backup/pricing

## At a glance

| | |
|---|---|
| Backup tool | restic 0.16+ (in nixpkgs) |
| Storage | Backblaze B2, bucket `UwU-Server-Backup` |
| Region | eu-central-003 (Hetzner Falkenstein / DE) |
| Schedule | Daily at 03:15 UTC, randomized ±30 min |
| Encryption | Client-side (restic), B2 server-side encryption **disabled** (redundant) |
| Retention | last 5 / daily 14 / weekly 8 / monthly 6 / yearly 2 |
| Alerting | Healthchecks.io ping (optional) |

## What gets backed up

- `/home/jaide` — projects, dotfiles, AI models, .config
- `/var/lib/gitea` — git repos + database
- `/var/lib/paperless` — scanned documents + database
- `/media/l1`, `/media/l2` — bulk media pools

## What is NOT backed up

- `/media/games` — reinstallable from Steam/GOG/etc. Saves ~$5/month
  on the B2 bill.
- `/media/backup` — local backup pool; backing it up to itself is
  circular and wastes bandwidth.
- `/nix/store` — reproducible from the flake; rerun `nixos-rebuild`
  on the new machine.
- The Nix store on `/nix/store` is also not backed up because
  everything in it is reproducible from `~/nixos` and the lock file.

## Restore — full system

The "house burned down" scenario. A new machine, fresh NixOS, want
my data back:

```bash
# 1. On the new host, install restic + sops + age
nix-shell -p restic sops age

# 2. Pull the sops secrets (you need jaide's YubiKey for the
#    age identity)
git clone git@github.com:JaideAirblade/nixos-secrets.git

# 3. Set env vars
export B2_ACCOUNT_ID=$(sops -d --extract '["b2_key_id"]' \
  nixos-secrets/secrets/UwU-Server/restic-b2.yaml)
export B2_ACCOUNT_KEY=$(sops -d --extract '["b2_application_key"]' \
  nixos-secrets/secrets/UwU-Server/restic-b2.yaml)
export RESTIC_REPOSITORY=b2:uwu-server-backup:backups
export RESTIC_PASSWORD=$(sops -d --extract '["restic_password"]' \
  nixos-secrets/secrets/UwU-Server/restic-b2.yaml)

# 4. Confirm the repo is readable
restic snapshots  # list available snapshots

# 5. Restore the most recent snapshot to /mnt/restore
sudo mkdir -p /mnt/restore
sudo restic restore latest --target /mnt/restore

# 6. Verify integrity (one-time check)
sudo restic check --read-data-subset=10%

# 7. Mount /mnt/restore into place (or selectively rsync
#    directories you want)
sudo rsync -av /mnt/restore/home/jaide/ /home/jaide/
sudo rsync -av /mnt/restore/var/lib/gitea/ /var/lib/gitea/
sudo rsync -av /mnt/restore/var/lib/paperless/ /var/lib/paperless/
```

## Restore — single file

For "I deleted the wrong file, I need the version from yesterday":

```bash
# Set env vars (steps 2–3 above), then:
restic restore <snapshot-id> --target /tmp/restore \
  --include /home/jaide/Projects/fpsbooster/some-file.py
```

Use `restic snapshots` to find the snapshot ID, or `latest` for the
most recent.

## Restore — browse without extracting

Sometimes you just want to look:

```bash
restic mount /tmp/restic-browse  # FUSE mount, read-only
ls /tmp/restic-browse/snapshots/<date>/home/jaide/
fusermount -u /tmp/restic-browse  # when done
```

## Verifying backups work

The restic module runs `restic check` automatically on Sundays (5%
of data is read and verified). For a deeper verification — picking
up a fresh failure mode the auto-check might miss — run manually:

```bash
sudo restic check --read-data-subset=100%
# Takes hours for a 3 TB repo, but catches every byte.
```

Schedule this quarterly via cron if you want the belt-and-suspenders
treatment.

## Cost so far

After ~6 months of steady-state, the prune policy keeps stored
bytes bounded. As of 2026-08-17:

- 0 snapshots (bucket just created, awaiting first backup)
- ~$0/mo until the first backup runs
- Estimated steady-state (3 TB source, dedup'd to ~1.5 TB stored):
  ~$9-12/mo

Track actual bill in the B2 dashboard → Account → Billing.

## Setup checklist (when UwU-Server is back)

```bash
# 1. Generate the restic repo password
restic -r b2:uwu-server-backup:backups init
# → prints a password; save it

# 2. Add secrets to sops (the backup module expects 4 keys):
#   secrets/UwU-Server/restic-b2.yaml:
#     b2_key_id: ...
#     b2_application_key: ...
#     restic_password: ...
#     healthchecks_ping_url: ...  # optional
sops secrets/UwU-Server/restic-b2.yaml

# 3. Re-key nixos-secrets (so the new file is decryptable by
#    UwU-Server's host key):
nix flake update nixos-secrets
sops updatekeys -y secrets/UwU-Server/restic-b2.yaml

# 4. Deploy UwU-Server:
just deploy-remote UwU-Server 10.10.0.1

# 5. Verify first backup runs:
ssh jaide@10.10.0.1 'systemctl list-timers restic*'
ssh jaide@10.10.0.1 'systemctl status restic-backups-b2.service'
```