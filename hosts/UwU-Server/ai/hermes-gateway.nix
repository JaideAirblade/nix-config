# Hermes Agent messaging gateway (Telegram, Discord, WhatsApp, Weixin).
#
# This module declares a user-scope systemd service that runs `hermes
# gateway` under the luna account. It is the equivalent of running
# `hermes gateway install` once, but expressed declaratively in the
# flake so a fresh `just deploy` always reproduces it (no imperative
# `hermes gateway install` step required).
#
# WHY declarative (per user preference): if we installed the gateway
# imperatively, the unit file would live at
# /home/luna/.config/systemd/user/hermes-gateway.service and would
# silently disappear on a clean re-install or migration. Putting it in
# the NixOS config means `nixos-rebuild switch` always re-creates it.
#
# LIFECYCLE:
#   - wantedBy = [ "default.target" ]: starts on user login / boot
#   - ConditionUser = "luna": only luna's session starts this unit
#   - Restart = "always": auto-restart on crash
#   - Lingering enabled via `loginctl enable-linger luna`, so the user
#     systemd manager runs even when luna is not at the greeter/TTY.
#
# SECURITY HARDENING (mirrors hermes-router + gdrive-sync playbook):
#   - ConditionUser = luna           (single-user scope)
#   - CapabilityBoundingSet empty   (no Linux capabilities)
#   - ProtectSystem = strict         (read-only /usr, /etc, /boot, …)
#   - ProtectHome = read-only        (HOME readable, writeable only via
#                                    ReadWritePaths)
#   - ReadWritePaths = ~/.hermes     (gateway needs to write sessions,
#                                    logs, config)
#   - NoNewPrivileges = true         (no setuid escalation)
#   - PrivateTmp = true              (isolated /tmp)
#   - PrivateDevices = true          (no /dev/sda, /dev/dri, etc.)
#   - RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6"
#                                 (HTTPS out for messaging platforms)
#
# Per-platform setup (after deploy) is a follow-up task — see
# tests/server-hermes-gateway-regressions.py for the security contract.
#
# Usage:
#   systemctl --user status hermes-gateway
#   journalctl --user -u hermes-gateway -f
#   hermes gateway status            # Hermes CLI confirms it's running
#   hermes gateway setup             # Configure platforms after deploy
{ inputs, ... }:
{
  nixos.hosts."UwU-Server" =
    { config, lib, pkgs, ... }:
    {
      # Loginctl lingering — required so luna's systemd --user manager
      # runs even when luna is logged out. Without it, the hermes-gateway
      # unit never auto-starts (the manager doesn't exist between
      # sessions). It MUST be enabled with `sudo loginctl enable-linger
      # luna` and persists in /var/lib/systemd/linger/luna. That command
      # is run once on this server (and the directory is in /var/lib,
      # so it survives reboots). To make it Nix-managed, follow up
      # with a `systemd.tmpfiles.rules` entry that creates the linger
      # file as a Nix-managed artifact.
      systemd.user.services.hermes-gateway = {
        description = "Hermes Agent messaging gateway (Telegram/Discord/etc.)";
        documentation = [ "https://hermes-agent.nousresearch.com/docs" ];

        unitConfig.ConditionUser = "luna";

        wantedBy = [ "default.target" ];

        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.hermes-agent}/bin/hermes gateway run";

          # Auto-restart on crash. RestartSec keeps tight crash loops
          # from spamming the journal.
          Restart = "always";
          RestartSec = "10s";

          # Hardening — see module header for rationale. Mirrors the
          # profile used by hermes-router and the gdrive-sync service.
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

          # NOT setting MemoryDenyWriteExecute=true: hermes CLI uses
          # Python + node sub-processes that legitimately JIT / mmap.
          # hermes-router.nix leaves this off for the same reason.

          # Gateway needs HOME=/home/luna so it picks up ~/.hermes/.env
          # and ~/.hermes/config.yaml.
          Environment = [
            "HOME=/home/luna"
            "PATH=/run/current-system/sw/bin:/home/luna/.nix-profile/bin"
          ];
        };
      };
    };
}
