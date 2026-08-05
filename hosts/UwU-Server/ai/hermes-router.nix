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

      minimaxImageUpstream = pkgs.fetchFromGitHub {
        owner = "rriggs";
        repo = "hermes-plugin-minimax-image";
        rev = "5a07a0f67d74a67ac426d7b901f8bfc60f28951c";
        hash = "sha256-Tj8m243EmV8legIQyfGvGkfIze5l7bAtbCWQ5gyqhxA=";
      };

      minimaxImageSource = pkgs.applyPatches {
        name = "hermes-plugin-minimax-image-reviewed-source";
        src = minimaxImageUpstream;
        patches = [ ./patches/minimax-image-managed-media-only.patch ];
      };

      minimaxVideoUpstream = pkgs.fetchFromGitHub {
        owner = "rriggs";
        repo = "hermes-plugin-minimax-video";
        rev = "759bec0f124c50e868facc8da5e6cf054403d761";
        hash = "sha256-fWwmtBubTvxQ2LZyftGwWD0IzC1nY6EIl0kBqUrtKd0=";
      };

      minimaxVideoSource = pkgs.applyPatches {
        name = "hermes-plugin-minimax-video-reviewed-source";
        src = minimaxVideoUpstream;
        patches = [ ./patches/minimax-video-managed-media-only.patch ];
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
      minimaxImagePluginPath = "/home/jaide/.hermes/plugins/minimax-image";
      minimaxVideoPluginPath = "/home/jaide/.hermes/plugins/minimax-video";
      localMinimaxImagePluginPath = "/home/jaide/.hermes/profiles/local/plugins/minimax-image";
      localMinimaxVideoPluginPath = "/home/jaide/.hermes/profiles/local/plugins/minimax-video";
      installHermesServerExtensions = pkgs.writeShellApplication {
        name = "install-hermes-server-extensions";
        runtimeInputs = [ pkgs.coreutils pkgs.hermes-agent ];
        text = ''
          set -euo pipefail
          skill_source=${lib.escapeShellArg "${mathViaCodeSource}/skills/math-via-code"}
          skill_path=${lib.escapeShellArg mathSkillPath}
          mnemosyne_source=${lib.escapeShellArg mnemosynePluginSource}
          local_plugin_path=${lib.escapeShellArg localMnemosynePluginPath}
          minimax_image_source=${lib.escapeShellArg minimaxImageSource}
          minimax_video_source=${lib.escapeShellArg minimaxVideoSource}
          minimax_image_path=${lib.escapeShellArg minimaxImagePluginPath}
          minimax_video_path=${lib.escapeShellArg minimaxVideoPluginPath}
          local_minimax_image_path=${lib.escapeShellArg localMinimaxImagePluginPath}
          local_minimax_video_path=${lib.escapeShellArg localMinimaxVideoPluginPath}

          preflight_target_parent() {
            local target="$1"
            local parent
            parent="$(dirname -- "$target")"
            while [[ "$parent" != "/" ]]; do
              if [[ -L "$parent" ]]; then
                printf 'refusing symlinked parent for managed Hermes target: %s\n' "$target" >&2
                exit 1
              fi
              parent="$(dirname -- "$parent")"
            done
          }

          managed_store_identity() {
            local path="$1"
            local relative
            local entry
            local name
            local tail=""
            [[ "$path" == /nix/store/* ]] || return 1
            relative="''${path#/nix/store/}"
            entry="''${relative%%/*}"
            [[ "$entry" == *-* ]] || return 1
            name="''${entry#*-}"
            if [[ "$relative" == */* ]]; then
              tail="/''${relative#*/}"
            fi
            printf '%s%s\n' "$name" "$tail"
          }

          preflight_managed_symlink() {
            local source="$1"
            local target="$2"
            local label="$3"
            local current_target
            local expected_target
            local current_identity
            local expected_identity

            preflight_target_parent "$target"
            expected_target="$(readlink -f -- "$source")"
            if [[ -L "$target" ]]; then
              current_target="$(readlink -f -- "$target" || true)"
              if [[ "$current_target" != "$expected_target" ]]; then
                current_identity="$(managed_store_identity "$current_target" || true)"
                expected_identity="$(managed_store_identity "$expected_target" || true)"
                if [[ -z "$current_identity" || "$current_identity" != "$expected_identity" ]]; then
                  printf 'refusing to replace unmanaged Hermes %s symlink: %s\n' "$label" "$target" >&2
                  exit 1
                fi
              fi
            elif [[ -e "$target" ]]; then
              printf 'refusing to replace unmanaged Hermes %s: %s\n' "$label" "$target" >&2
              exit 1
            fi
          }

          install_managed_symlink() {
            local source="$1"
            local target="$2"
            local current_target
            local expected_target
            local current_identity
            local expected_identity

            preflight_target_parent "$target"
            expected_target="$(readlink -f -- "$source")"
            if [[ -L "$target" ]]; then
              current_target="$(readlink -f -- "$target" || true)"
              if [[ "$current_target" == "$expected_target" ]]; then
                return
              fi
              current_identity="$(managed_store_identity "$current_target" || true)"
              expected_identity="$(managed_store_identity "$expected_target" || true)"
              [[ "$current_identity" == "$expected_identity" ]]
              ln -sfnT "$source" "$target"
              return
            fi
            install -d -m 0755 "$(dirname "$target")"
            preflight_target_parent "$target"
            ln -sT "$source" "$target"
          }

          # Preflight every managed target before any filesystem mutation.
          preflight_managed_symlink "$skill_source" "$skill_path" skill
          preflight_managed_symlink "$mnemosyne_source" "$local_plugin_path" plugin
          preflight_managed_symlink "$minimax_image_source" "$minimax_image_path" plugin
          preflight_managed_symlink "$minimax_video_source" "$minimax_video_path" plugin
          preflight_managed_symlink "$minimax_image_source" "$local_minimax_image_path" plugin
          preflight_managed_symlink "$minimax_video_source" "$local_minimax_video_path" plugin

          # Mutate only after every target has passed preflight.
          install_managed_symlink "$skill_source" "$skill_path"
          install_managed_symlink "$mnemosyne_source" "$local_plugin_path"
          install_managed_symlink "$minimax_image_source" "$minimax_image_path"
          install_managed_symlink "$minimax_video_source" "$minimax_video_path"
          install_managed_symlink "$minimax_image_source" "$local_minimax_image_path"
          install_managed_symlink "$minimax_video_source" "$local_minimax_video_path"

          hermes config set memory.provider mnemosyne

          configure_minimax_profile() {
            local profile_home="$HERMES_HOME"
            env HERMES_HOME="$profile_home" hermes plugins enable minimax-image >/dev/null
            env HERMES_HOME="$profile_home" hermes plugins enable minimax-video >/dev/null
            env HERMES_HOME="$profile_home" hermes config set image_gen.minimax.api https://api.minimax.io >/dev/null
            env HERMES_HOME="$profile_home" hermes config set image_gen.minimax.key_env MINIMAX_API_KEY >/dev/null
            env HERMES_HOME="$profile_home" hermes config set image_gen.minimax.model image-01 >/dev/null
            env HERMES_HOME="$profile_home" hermes config set video_gen.minimax.api https://api.minimax.io >/dev/null
            env HERMES_HOME="$profile_home" hermes config set video_gen.minimax.key_env MINIMAX_API_KEY >/dev/null
            env HERMES_HOME="$profile_home" hermes config set video_gen.minimax.model MiniMax-Hailuo-2.3 >/dev/null
          }

          HERMES_HOME=/home/jaide/.hermes configure_minimax_profile
          HERMES_HOME=/home/jaide/.hermes/profiles/local configure_minimax_profile
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
        {
          assertion = builtins.pathExists "${minimaxImageSource}/plugin.yaml";
          message = "Pinned MiniMax image source must contain the reviewed Hermes plugin manifest";
        }
        {
          assertion = builtins.pathExists "${minimaxVideoSource}/plugin.yaml";
          message = "Pinned MiniMax video source must contain the reviewed Hermes plugin manifest";
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
        restartUnits = [ "hermes-router.service" ];
      };

      system.build.hermesMinimaxImagePlugin = minimaxImageSource;
      system.build.hermesMinimaxVideoPlugin = minimaxVideoSource;
      system.build.hermesServerExtensionsInstaller = installHermesServerExtensions;

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
        requires = [ "hermes-local-profile.service" ];
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
