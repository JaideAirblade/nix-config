# Hermes WebUI — community web UI for Hermes Agent (nesquena/hermes-webui).
#
# Provides a browser-based chat interface that mirrors the Hermes CLI. Listens
# on 0.0.0.0:8080; the NixOS firewall restricts tailscale0 (peer access) and
# blocks eno1/loopback/public interfaces, so the WebUI is reachable only via
# the tailnet (matching the existing port-8080 ACL in tailscale-policy.json
# and the firewall rule in modules/network/tailscale-mesh.nix). This shape
# keeps future host additions (Caddy reverse-proxy, more services) from
# bumping against binding-IP state across hosts — access control lives in
# one place.
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
# Port choice: 8080 was previously llama-server (the local AI inference);
# 2026-08-06 port-rearchitecture moved llama off 8080 to 9001/9002 so
# the WebUI can take the conventional "primary HTTP UI" port alongside
# future services (Caddy reverse-proxy, music server). See commit message.
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

        # Network binding — listen on 0.0.0.0; access control is delegated
        # to the NixOS firewall (modules/network/tailscale-mesh.nix +
        # modules/network/tailscale-policy.json). Keeps the host/port
        # configuration host-agnostic so Caddy/other reverse proxies can
        # sit in front of multiple services later without per-host
        # re-binding gymnastics.
        host = "0.0.0.0";
        port = 8080;
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

        # Workspace — pin to a luna-owned path OUTSIDE /var. The upstream
        # WebUI's _discover_default_workspace() walks:
        #   1. HERMES_WEBUI_DEFAULT_WORKSPACE env var (this)
        #   2. ~/workspace (existing)
        #   3. ~/work (existing)
        #   4. ~/workspace (create)
        #   5. <stateDir>/workspace   ← BUG: stateDir is /var/lib/hermes-webui,
        #                                workspace.py's deny-list rejects /var/*
        # Setting this env var short-circuits the discovery to step 1, so
        # the upstream bug never fires. This env var is NOT in the upstream
        # NixOS module's protectedEnvironment list, so extraEnvironment is
        # the right channel (not environmentFiles, which would be rejected).
        extraEnvironment.HERMES_WEBUI_DEFAULT_WORKSPACE = "/home/luna/workspace";
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
