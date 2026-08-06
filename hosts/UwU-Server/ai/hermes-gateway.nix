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
#     (NixOS auto-creates default.target as the user-session default)
#   - ConditionUser = "luna": only luna's session starts this unit
#   - Restart = "always": auto-restart on crash
#   - StateDirectory = "hermes-gateway": writable persistent state
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
#                                 (no exotic sockets)
#
# PER-PLATFORM SETUP (after deploy):
#   Hermes gateway reads platform creds from ~/.hermes/.env (sops-style).
#   To enable a platform:
#     1. sops secrets/UwU-Server/hermes-gateway-<platform>.yaml
#     2. add a sops.templates block in hermes-webui.nix style
#     3. git commit + just deploy
#   Out of scope for this turn — only declares the service skeleton.
#
# USAGE:
#   systemctl --user status hermes-gateway
#   journalctl --user -u hermes-gateway -f
#   hermes gateway status            # Hermes CLI confirms it's running
#   hermes gateway setup             # Configure platforms after deploy
{
  config,
  pkgs,
  lib,
  ...
}:

{
  systemd.user.services.hermes-gateway = {
    description = "Hermes Agent messaging gateway (Telegram/Discord/etc.)";
    documentation = [ "https://hermes-agent.nousresearch.com/docs" ];

    unitConfig.ConditionUser = "luna";

    wantedBy = [ "default.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.hermes-agent}/bin/hermes gateway run";

      # Auto-restart on crash (RateLimit protects against restart loops).
      Restart = "always";
      RestartSec = "10s";

      # Hardening — see module header for rationale.
      CapabilityBoundingSet = [ "" ];
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = [
        "/home/luna/.hermes"
        "/home/luna/.cache"
        "/home/luna/.local/share/hermes-gateway"
      ];
      StateDirectory = "hermes-gateway";
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

      # NOT setting MemoryDenyWriteExecute=true: hermes CLI uses Python+node
      # sub-processes that legitimately JIT/mmap. hermes-router.nix leaves
      # this off for the same reason — keep consistent.

      # Gateway needs HOME=/home/luna so it picks up ~/.hermes/.env and
      # ~/.hermes/config.yaml. systemd's %h is the invoking user's home;
      # setting HOME explicitly removes any ambiguity when the unit is
      # started under `sudo --user luna`.
      Environment = [
        "HOME=/home/luna"
        "PATH=/run/current-system/sw/bin:/home/luna/.nix-profile/bin"
      ];
    };
  };
}
