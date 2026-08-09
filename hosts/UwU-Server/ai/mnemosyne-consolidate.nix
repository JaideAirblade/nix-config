# Mnemosyne memory consolidation cron.
#
# Runs `hermes mnemosyne sleep --all-sessions` daily to consolidate
# aged-out working memories into episodic summaries + vectors.
#
# Mnemosyne's default cutoff is half of WORKING_MEMORY_TTL_HOURS (168h
# default → 84h = 3.5 days). We override MNEMOSYNE_WM_TTL_HOURS=48 so
# the cutoff drops to 24h — anything older than a day gets consolidated
# nightly. Working-memory recall still uses the full TTL for relevance
# ranking; this only affects which rows sleep() considers "old".
#
# Runs under the luna account (where ~/.hermes lives). Uses the system
# hermes binary (post-nixos-rebuild switch) which has sqlite-vec wired
# in via mnemosyne.overlay.nix.
#
# Security: mirrors the hermes-gateway.nix hardening profile
# (ProtectHome=read-only + ReadWritePaths, no capabilities, no
# network access beyond loopback embeddings API).
#
# Lifecycle:
#   - wantedBy = [ "timers.target" ]: starts via the user timer
#   - ConditionUser = "luna": only luna's session runs this unit
#   - Persistent = true on the timer: catches missed runs after downtime
#
# Usage:
#   systemctl --user status mnemosyne-consolidate
#   systemctl --user list-timers
#   journalctl --user -u mnemosyne-consolidate -f
#   hermes mnemosyne stats     # watch working/episodic counts
{ pkgs, ... }:
{
  nixos.hosts."UwU-Server" =
    { config, ... }:
    {
      systemd.user.services.mnemosyne-consolidate = {
        description = "Mnemosyne memory consolidation (sleep cycle)";
        documentation = [ "https://hermes-agent.nousresearch.com/docs" ];

        unitConfig.ConditionUser = "luna";

        serviceConfig = {
          Type = "oneshot";

          # Run via the deployed hermes binary so PYTHONPATH includes
          # sqlite-vec. --all-sessions scans every bank so cross-session
          # consolidation happens regardless of which profile owns the
          # memory. force=false (default) honors the age cutoff.
          ExecStart = "${pkgs.hermes-agent}/bin/hermes mnemosyne sleep --all-sessions";

          # Hardening — same profile as hermes-gateway.nix.
          CapabilityBoundingSet = [ "" ];
          ProtectSystem = "strict";
          ProtectHome = "read-only";
          ReadWritePaths = [
            "/home/luna/.hermes"
            "/home/luna/.cache"
          ];
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];

          # systemd --user managers don't get CPU/memory accounting by
          # default; this avoids pinning the timer if the host is under
          # pressure when it fires.
          Nice = 10;
          IOSchedulingClass = "best-effort";
          IOSchedulingPriority = 7;
        };

        # Override the TTL so the 24h cutoff applies. The hermes binary
        # already has MNEMOSYNE_EMBEDDING_API_URL/MODEL/DIM in
        # /etc/pam/environment (wired in hermes-router.nix), so the
        # embedding server is reachable without explicit exports.
        environment.MNEMOSYNE_WM_TTL_HOURS = "48";
      };

      systemd.user.timers.mnemosyne-consolidate = {
        description = "Daily Mnemosyne memory consolidation";
        wantedBy = [ "timers.target" ];

        timerConfig = {
          # Run at 04:17 daily — off-peak, varied minute avoids
          # synchronized spikes with other timers (drive-integrity at
          # 03:00, honcho-backup daily, etc).
          OnCalendar = "*-*-* 04:17:00";
          RandomizedDelaySec = "15m";
          Persistent = true;
          Unit = "mnemosyne-consolidate.service";
        };
      };
    }
  ;
}