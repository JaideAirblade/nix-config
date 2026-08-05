# Hermes WebUI — community web UI for Hermes Agent (nesquena/hermes-webui).
#
# Provides a browser-based chat interface that mirrors the Hermes CLI. Runs
# bound to the Tailscale IP only — not on 0.0.0.0 — so it is reachable from
# any device on the user's tailnet (phone, work laptop) but never from the
# public internet, regardless of any NAT or router configuration.
#
# Runs as user `luna` so it shares the same ~/.hermes/ state as the on-host
# hermes-agent sessions AND the hermes-router provider. That means the WebUI
# sees the same Mnemosyne-backed memory, the same sessions, the same
# profile/model setup, and the same provider pool. Hardening follows the
# `hermes-router.nix` template (ProtectHome=read-only + ReadWritePaths
# for ~/.hermes only), so the WebUI cannot reach anything in /home/luna
# besides its own Hermes state.
#
# Authentication: password is loaded from sops (HERMES_WEBUI_PASSWORD), so
# even if a phone or work laptop is briefly on an untrusted network (e.g. a
# coffee shop), the tailnet is gated by an attacker-needs-to-know password.
# The fire-and-forget alternative would be to rely on Tailscale's token
# alone, which is fine for laptops but weak for phones that get handed
# around.
#
# NOT enabled by default for flake-managed test hosts — only the canonical
# "luna" user on UwU-Server benefits, so this module is registered against
# `nixos.hosts."UwU-Server"` and not `nixos.modules.common`.
#
# The Tailscale IP `100.102.183.94` is hardcoded inline below. If Tailscale
# rotates it, run `tailscale ip -4` on the live host to find the new value
# and re-build.
{ inputs, ... }:
{
  nixos.hosts."UwU-Server" =
    { config, lib, pkgs, ... }:
    {
      imports = [ inputs.hermes-webui.nixosModules.default ];

      # Hand the WebUI its password via a sops template. The .env file
      # ends up at /var/lib/hermes-webui/webui-password with mode 0400,
      # so it is readable only by the service user. To rotate the password,
      # edit the sops file in nixos-secrets and re-build.
      sops.templates.hermes-webui-password = {
        content = ''
          HERMES_WEBUI_PASSWORD=${config.sops.placeholder.hermes_webui_password}
        '';
        owner = "luna";
        group = "users";
        mode = "0400";
        restartUnits = [ "hermes-webui.service" ];
      };
      sops.secrets.hermes_webui_password = {
        sopsFile = "${inputs.nixos-secrets}/secrets/UwU-Server/hermes-webui.yaml";
        key = "hermes_webui_password";
      };

      services.hermes-webui = {
        enable = true;

        # Wire the WebUI to the SAME hermes-agent that the Tailscale-routed
        # Luna users and the hermes-router provider use. passthru.hermesVenv
        # is exposed by the upstream hermes-agent overlay, so the WebUI's
        # Python resolves to: pyyaml + cryptography + every Hermes dep
        # (including mnemosyne_hermes from mnemosyne.overlay.nix).
        agent.package = pkgs.hermes-agent;

        # Network binding — Tailscale-only. host = "100.102.183.94"
        # (the Tailscale IP of UwU-Server) means the listener never hits
        # 0.0.0.0; nothing outside the tailnet can reach it. No firewall
        # port-forward needed and openFirewall stays false.
        host = "100.102.183.94";
        port = 8787;
        openFirewall = false;

        # Share Luna's Hermes home directory. Both the hermes-router
        # provider and the on-host hermes-agent SSH sessions write here,
        # so the WebUI sees the same Mnemosyne memory, sessions, and
        # provider config without any sync step.
        hermesHome = "/home/luna/.hermes";

        # Run as luna (matches hermes-server-extensions convention) so the
        # WebUI can read/write ~/.hermes without UNIX-permission gymnastics.
        user = "luna";
        group = "users";

        # Per-device state — config, login sessions, passkeys, settings.json.
        # Lives outside ~/.hermes so it can be wiped independently of session
        # data, and has a backup-friendly default.
        stateDir = "/var/lib/hermes-webui";

        # Auth — password loaded from the sops template above.
        environmentFiles = [ config.sops.templates.hermes-webui-password.path ];
      };

      # The upstream module already sets a sensible systemd unit; we layer
      # extra hardening on top so the WebUI is as locked down as
      # hermes-router. NoNewPrivileges + ProtectHome=read-only +
      # ReadWritePaths limited to Hermes state + ProtectSystem=strict.
      systemd.services.hermes-webui = {
        serviceConfig = {
          EnvironmentFile = [ config.sops.templates.hermes-webui-password.path ];
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = "read-only";
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          ProtectSystem = "strict";
          ReadWritePaths = [
            "/home/luna/.hermes"
            "/var/lib/hermes-webui"
          ];
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          CapabilityBoundingSet = "";
          AmbientCapabilities = "";
        };
      };
    };
}
