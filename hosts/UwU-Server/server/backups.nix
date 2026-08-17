# Off-site backups via restic → Backblaze B2.
#
# Backs up UwU-Server's irreplaceable state to a private B2 bucket
# (`UwU-Server-Backup`, eu-central-003 region — co-located with
# Hetzner Falkenstein). Encryption is client-side via restic (the
# repo file format is encrypted before upload; B2's "Encryption:
# Disabled" setting is intentional and correct).
#
# ## Why restic + B2 (not Computer Backup)
#
# - **Declarative**: services.restic.backups is a NixOS module — the
#   schedule, paths, retention, and pre-backup hooks live in this
#   file. No opaque daemon, no manual rotation.
# - **Deduplication**: restic's chunk-level dedup keeps incremental
#   snapshots small. A typical 3 TB working set compresses to ~1.5 TB
#   stored after a few weeks of stable data.
# - **Encrypted client-side**: the repo on B2 is unreadable without
#   the restic password, which lives in sops. B2's "Encryption:
#   Disabled" simply means we don't double-encrypt at-rest with B2's
#   server-side keys (would be redundant).
# - **Predictable cost**: $6/TB-month storage + occasional egress.
#   See `pkgs/.update-config.json` for budget tracking.
#
# ## B2 connection
#
# Backblaze B2 application key + keyID live in sops at
# `secrets/UwU-Server/restic-b2.yaml`. The key has:
#   - `listBuckets`, `listFiles`, `readFiles`, `writeFiles`,
#     `deleteFiles` on the `UwU-Server-Backup` bucket only
#   - NO `listAllBuckets` (blast radius = this bucket)
#
# Generate the key in B2 dashboard → App Keys → Add New Key →
# bucket-specific. Paste keyID + applicationKey into sops:
#
#   $ nix shell nixpkgs#sops -c sops secrets/UwU-Server/restic-b2.yaml
#   b2_key_id: ...
#   b2_application_key: ...
#   restic_password: ...  # `restic -g random -o b2.repository=...
#                          #        init` will print one; save that
#
# ## What's backed up
#
# - `/home/jaide` — projects, dotfiles, AI models, .config
# - `/var/lib/gitea` — git repos + DB (Gitea runs as a service on
#   UwU-Server; the on-disk repo is irreplaceable)
# - `/var/lib/paperless` — scanned documents + DB
# - `/media/l1`, `/media/l2` — bulk media pools (dedup'd well by restic)
#
# Explicitly **not** backed up:
# - `/media/games` — reinstallable from Steam/GOG/etc. Saves ~$5/month.
# - `/media/backup` — this is the LOCAL backup pool; backing it up to
#   itself would be circular.
#
# ## Schedule
#
# Daily at 03:15 UTC, well after restic-prune (which runs before each
# backup automatically via NixOS module). Random delay prevents
# thundering-herd on B2 if multiple hosts ever share a bucket.
#
# ## Retention
#
# restic's `--keep-*` flags (set via NixOS module's `pruneOpts`):
#   - keep-last 5    (always keep the 5 most recent snapshots)
#   - keep-daily 14  (2 weeks of daily)
#   - keep-weekly 8  (8 weeks of weekly)
#   - keep-monthly 6 (6 months of monthly)
#   - keep-yearly 2  (2 years of yearly)
#
# After ~6 months steady-state, stored bytes plateau instead of growing
# linearly. Critical for B2 cost predictability.
#
# ## Healthchecks.io ping
#
# After a successful backup, the script pings a Healthchecks.io URL
# so you get alerted if backups silently stop running. The URL lives
# in sops (`healthchecks_backup_ping` key). Failing pings also stop
# the script from claiming success, so a dead backup is loud.
_:
{
  nixos.hosts."UwU-Server" =
    { config, lib, pkgs, ... }:

    {
      # Backblaze B2 application key + restic password live in sops at
      # `secrets/UwU-Server/restic-b2.yaml`. The secret file is read
      # by sops-nix at activation time, so as long as the file exists
      # at the configured sopsFile path, these declarations work.
      #
      # The required keys in that YAML are:
      #   b2_key_id            : B2 application key ID
      #   b2_application_key   : B2 application key (secret)
      #   restic_password      : restic repo password (run `restic
      #                          -g random init` once to get one)
      # Optional:
      #   healthchecks_ping_url: Healthchecks.io URL to ping on
      #                          successful backup. If absent, the
      #                          post-backup script silently no-ops.
      sops.secrets.restic_b2_key_id = {
        sopsFile = ../../../secrets/UwU-Server/restic-b2.yaml;
        key = "b2_key_id";
        owner = "root";
        group = "root";
        mode = "0400";
      };

      sops.secrets.restic_b2_application_key = {
        sopsFile = ../../../secrets/UwU-Server/restic-b2.yaml;
        key = "b2_application_key";
        owner = "root";
        group = "root";
        mode = "0400";
      };

      sops.secrets.restic_password = {
        sopsFile = ../../../secrets/UwU-Server/restic-b2.yaml;
        key = "restic_password";
        owner = "root";
        group = "root";
        mode = "0400";
      };

      # Sops-templated environment file for restic. Sets B2 creds +
      # restic repo URL + password so the unit can use them without
      # inline secrets in the Nix store.
      sops.templates.restic-b2-env = {
        content = ''
          B2_ACCOUNT_ID=${config.sops.placeholder.restic_b2_key_id}
          B2_ACCOUNT_KEY=${config.sops.placeholder.restic_b2_application_key}
          RESTIC_REPOSITORY=b2:uwu-server-backup:backups
          RESTIC_PASSWORD_FILE=${config.sops.placeholder.restic_password}
        '';
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "restic-backups-b2.service" ];
      };

      services.restic.backups.b2 = {
        enable = true;
        # Timer fires daily at 03:15 UTC. Random delay so multiple
        # hosts (future) don't hammer B2 at the same instant.
        timerConfig = {
          OnCalendar = "03:15";
          RandomizedDelaySec = "30m";
          Persistent = true;
        };

        # The `EnvironmentFile` is what carries B2_ACCOUNT_ID, B2_ACCOUNT_KEY,
        # RESTIC_REPOSITORY, and RESTIC_PASSWORD_FILE — set above via
        # sops.templates.restic-b2-env. Restic reads them automatically.
        environmentFile = config.sops.templates.restic-b2-env.path;

        # Paths to back up. `/media/games` and `/media/backup` are
        # explicitly excluded (see module header).
        paths = [
          "/home/jaide"
          "/var/lib/gitea"
          "/var/lib/paperless"
          "/media/l1"
          "/media/l2"
        ];

        # Prune + retention policy. restic's `--keep-*` flags rotate
        # snapshots to bound storage growth — without this the bill
        # grows linearly with snapshot count.
        pruneOpts = [
          "--keep-last" "5"
          "--keep-daily" "14"
          "--keep-weekly" "8"
          "--keep-monthly" "6"
          "--keep-yearly" "2"
        ];

        # Backup-time options. `--exclude-caches` skips directories
        # tagged with the CACHEDIR.TAG convention (cache dirs that
        # restic can rebuild). `--tag` adds tags to the snapshot for
        # easier filtering.
        backupOpts = [
          "--exclude-caches"
          "--tag" "automated"
          "--tag" "uwu-server"
        ];

        # Verification: every Sunday, also run `restic check` to
        # verify the repo's integrity. Catches bitrot in the
        # encrypted blob on B2.
        checkOpts = [
          "--read-data-subset=5%"
        ];

        # Post-backup hook: optionally ping a healthcheck URL if the env
      # var is set (operators can add it via systemd drop-in or
      # override file without touching this module). Failures
      # here are non-fatal — restic has already succeeded.
        postPostRestoreScript = ''
          if [ -n "''${HEALTHCHECKS_BACKUP_PING_URL:-}" ]; then
            ${pkgs.curl}/bin/curl --silent --show-error --fail --max-time 10 \
              -X GET "$HEALTHCHECKS_BACKUP_PING_URL" \
              || echo "restic: healthchecks ping failed (non-fatal)"
          fi
        '';

        # Run as root (restic needs to read /var/lib/gitea etc.).
        user = "root";
      };

      # Restic binary on PATH for ad-hoc commands (manual snapshot,
      # browse repo, mount for restore, etc.).
      environment.systemPackages = [ pkgs.restic ];
    }
  ;
}