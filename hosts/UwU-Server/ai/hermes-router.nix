# Server-only Hermes extensions: hardened multi-provider router and reviewed skills.
{ inputs, ... }:
{
  nixos.hosts."UwU-Server" =
    { config, lib, pkgs, ... }:

    let
      hermesRouterUpstream = pkgs.fetchFromGitHub {
        owner = "Shaf2665";
        repo = "Hermes-router";
        rev = "cc7ef00b5750416376b33c919406055d70275f9f";
        hash = "sha256-O7YyUK4V9y60Tcj/VkrWzE1pQOQllHUw91rlUE096i8=";
      };

      hermesRouterSource = pkgs.applyPatches {
        name = "hermes-router-reviewed-source";
        src = hermesRouterUpstream;
        patches = [ ./patches/hermes-router-disable-admin-surfaces.patch ];
      };

      mathViaCodeUpstream = pkgs.fetchFromGitHub {
        owner = "tommulkins";
        repo = "hermes-skill-math-via-code";
        rev = "35ad332ae18aea7623df2829df9c4003cba88ba4";
        hash = "sha256-qJJxQ+E8RkYwEPX93tG783Ixq+gqYwpW7mYjXLp1o04=";
      };

      mathViaCodeSource = pkgs.applyPatches {
        name = "math-via-code-reviewed-source";
        src = mathViaCodeUpstream;
        patches = [ ./patches/math-via-code-secure-tempdir.patch ];
      };

      mnemosynePluginSource = "${pkgs.python312Packages.mnemosyne-hermes}/lib/python3.12/site-packages/mnemosyne_hermes";

      routerPython = pkgs.python312.withPackages (ps: [
        ps.flask
        ps.requests
        ps.tiktoken
        ps.waitress
      ]);

      hermesRouter = pkgs.writeShellApplication {
        name = "hermes-router";
        runtimeInputs = [ routerPython ];
        text = ''
          exec python ${lib.escapeShellArg "${hermesRouterSource}/router.py"}
        '';
      };

      mathSkillPath = "/home/jaide/.hermes/skills/software-development/math-via-code";
      localMnemosynePluginPath = "/home/jaide/.hermes/profiles/local/plugins/mnemosyne";
      installHermesServerExtensions = pkgs.writeShellApplication {
        name = "install-hermes-server-extensions";
        runtimeInputs = [ pkgs.coreutils pkgs.hermes-agent ];
        text = ''
          set -euo pipefail
          skill_source=${lib.escapeShellArg "${mathViaCodeSource}/skills/math-via-code"}
          skill_path=${lib.escapeShellArg mathSkillPath}
          mnemosyne_source=${lib.escapeShellArg mnemosynePluginSource}
          local_plugin_path=${lib.escapeShellArg localMnemosynePluginPath}

          install -d -m 0755 "$(dirname "$skill_path")"
          if [[ -e "$skill_path" && ! -L "$skill_path" ]]; then
            printf 'refusing to replace unmanaged Hermes skill: %s\n' "$skill_path" >&2
            exit 1
          fi
          ln -sfnT "$skill_source" "$skill_path"

          install -d -m 0755 "$(dirname "$local_plugin_path")"
          if [[ -e "$local_plugin_path" && ! -L "$local_plugin_path" ]]; then
            printf 'refusing to replace unmanaged Hermes plugin: %s\n' "$local_plugin_path" >&2
            exit 1
          fi
          ln -sfnT "$mnemosyne_source" "$local_plugin_path"

          if [[ -f /home/jaide/.hermes/config.yaml ]]; then
            hermes config set memory.provider mnemosyne
          fi
        '';
      };
    in
    {
      assertions = [
        {
          assertion = builtins.pathExists "${hermesRouterSource}/router.py";
          message = "Pinned Hermes Router source must contain router.py";
        }
        {
          assertion = builtins.pathExists "${mathViaCodeSource}/skills/math-via-code/SKILL.md";
          message = "Pinned math-via-code source must contain the reviewed Hermes skill";
        }
      ];

      users.groups.hermes-router = { };
      users.users.hermes-router = {
        isSystemUser = true;
        group = "hermes-router";
        home = "/var/lib/hermes-router";
        createHome = false;
      };

      sops.secrets.hermes_router_proxy_api_key = {
        sopsFile = "${inputs.nixos-secrets}/secrets/UwU-Server/hermes-router.yaml";
        key = "hermes_router_proxy_api_key";
      };

      sops.templates.hermes-router-env = {
        content = ''
          PROXY_API_KEYS=${config.sops.placeholder.hermes_router_proxy_api_key}
        '';
        owner = "hermes-router";
        group = "hermes-router";
        mode = "0400";
      };

      systemd.services.hermes-router = {
        description = "Hardened local Hermes multi-provider router";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        environment = {
          HOST = "127.0.0.1";
          PORT = "8319";
          CACHE_TTL_SECONDS = "0";
          CACHE_PERSIST = "0";
          AUTO_DISCOVER_MODELS = "0";
          HERMES_ADMIN_SURFACES = "0";
          REQUEST_LOG_SIZE = "0";
          METRICS_REQUIRE_AUTH = "1";
          ROUTER_AUTH_FILE = "/var/lib/hermes-router/auth.json";
          ROUTER_STATE_FILE = "/var/lib/hermes-router/router_state.json";
          HERMES_INSTANCES_FILE = "/var/lib/hermes-router/instances.json";
          HR_ENV_FILE = "/var/lib/hermes-router/runtime.env";
          CODEX_MODEL = "gpt-5.6-sol";
        };
        serviceConfig = {
          User = "hermes-router";
          Group = "hermes-router";
          StateDirectory = "hermes-router";
          StateDirectoryMode = "0700";
          WorkingDirectory = "/var/lib/hermes-router";
          EnvironmentFile = config.sops.templates.hermes-router-env.path;
          ExecStart = lib.getExe hermesRouter;
          Restart = "on-failure";
          RestartSec = "5s";
          UMask = "0077";
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          ProtectSystem = "strict";
          ProcSubset = "pid";
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          CapabilityBoundingSet = "";
          AmbientCapabilities = "";
        };
      };

      systemd.services.hermes-server-extensions = {
        description = "Install pinned extensions for Jaide's server Hermes session";
        after = [ "hermes-local-profile.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "jaide";
          Group = "users";
          Environment = "HOME=/home/jaide";
          ExecStart = lib.getExe installHermesServerExtensions;
          UMask = "0022";
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
          ProtectSystem = "strict";
          ReadWritePaths = [ "/home/jaide/.hermes" ];
          RestrictAddressFamilies = [ "AF_UNIX" ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          CapabilityBoundingSet = "";
          AmbientCapabilities = "";
        };
      };
    }
  ;
}
