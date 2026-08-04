# Fully local Hermes + Honcho memory stack for UwU-Server.
#
# Model-specific inference settings follow:
#   https://unsloth.ai/docs/models/nemotron-3
#
# Trust boundaries:
# - Honcho API is published only on 127.0.0.1:8000.
# - PostgreSQL and Redis remain inside the private Compose network.
# - llama.cpp listens on all host interfaces so Docker can reach it, but the
#   firewall permits 8080/8082 only through honcho0 (loopback remains local).
# - Jaide is deliberately not placed in the root-equivalent docker group.
# - Model artifacts are downloaded outside the Nix store and verified against
#   immutable upstream revisions and SHA-256 digests before activation.
{ inputs, ... }:
{
  nixos.hosts."UwU-Server" =
    { config, lib, pkgs, ... }:

    let
      # Upstream tag v3.0.12 resolves to this commit. Keep the value visible so
      # regression review can detect a tag retarget or accidental source bump.
      honchoCommit = "5ad22840d829878f9ac4d13e9538e5fef216c97e";
      honchoImage = "uwu-honcho:3.0.12-${builtins.substring 0 12 honchoCommit}";
      modelDirectory = "/var/lib/local-ai/models";
      nemotronFile = "Nemotron-3-Nano-30B-A3B-UD-Q4_K_XL.gguf";
      embeddingFile = "Qwen3-Embedding-0.6B-Q8_0.gguf";
      nemotronAlias = "unsloth/Nemotron-3-Nano-30B-A3B";
      embeddingAlias = "qwen3-embedding-0.6b";
      containerModelBaseUrl = "http://host.docker.internal:8080/v1";
      containerEmbeddingBaseUrl = "http://host.docker.internal:8082/v1";
      envRef = name: "$" + "{${name}}";
      dbPasswordRef = envRef "HONCHO_DB_PASSWORD";

      modelDownloader = pkgs.writeShellApplication {
        name = "download-local-ai-models";
        runtimeInputs = [
          pkgs.aria2
          pkgs.coreutils
          pkgs.util-linux
        ];
        text = ''
          set -euo pipefail
          umask 0027

          model_dir=${lib.escapeShellArg modelDirectory}
          mkdir -p "$model_dir"

          download_model() {
            local name="$1"
            local url="$2"
            local expected_sha256="$3"
            local expected_bytes="$4"
            local destination="$model_dir/$name"
            local partial="$destination.part"

            if [[ -f "$destination" ]]; then
              actual_bytes=$(stat -c %s "$destination")
              if [[ "$actual_bytes" == "$expected_bytes" ]] \
                && printf '%s  %s\n' "$expected_sha256" "$destination" | sha256sum --check --status; then
                printf 'verified existing model: %s\n' "$name"
                return 0
              fi
              printf 'refusing invalid existing model: %s\n' "$destination" >&2
              return 1
            fi

            aria2c \
              --allow-overwrite=true \
              --auto-file-renaming=false \
              --continue=true \
              --dir="$model_dir" \
              --file-allocation=none \
              --max-connection-per-server=8 \
              --min-split-size=16M \
              --out="$name.part" \
              --split=8 \
              "$url"

            actual_bytes=$(stat -c %s "$partial")
            [[ "$actual_bytes" == "$expected_bytes" ]] || {
              printf 'size mismatch for %s: expected %s, got %s\n' \
                "$name" "$expected_bytes" "$actual_bytes" >&2
              rm -f "$partial" "$partial.aria2"
              return 1
            }
            printf '%s  %s\n' "$expected_sha256" "$partial" | sha256sum --check --status || {
              printf 'SHA-256 mismatch for %s\n' "$name" >&2
              rm -f "$partial" "$partial.aria2"
              return 1
            }
            mv -T "$partial" "$destination"
            chmod 0640 "$destination"
            printf 'downloaded and verified model: %s\n' "$name"
          }

          exec 9>"$model_dir/.download.lock"
          flock 9

          download_model \
            ${lib.escapeShellArg nemotronFile} \
            ${lib.escapeShellArg "https://huggingface.co/unsloth/Nemotron-3-Nano-30B-A3B-GGUF/resolve/9ad8b366c308f931b2a96b9306f0b41aef9cd405/${nemotronFile}?download=true"} \
            627f5b04aedc97f967332f331bd75b7a4ed2f33ca83e6ee74b44235cc1887890 \
            22833947424

          download_model \
            ${lib.escapeShellArg embeddingFile} \
            ${lib.escapeShellArg "https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF/resolve/370f27d7550e0def9b39c1f16d3fbaa13aa67728/${embeddingFile}?download=true"} \
            06507c7b42688469c4e7298b0a1e16deff06caf291cf0a5b278c308249c3e439 \
            639150592
        '';
      };

      commonLlamaService = {
        after = [ "local-ai-models.service" "network.target" ];
        requires = [ "local-ai-models.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "local-ai";
          Group = "local-ai";
          SupplementaryGroups = [ "render" "video" ];
          Restart = "on-failure";
          RestartSec = "5s";
          TimeoutStartSec = "10min";
          UMask = "0027";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectSystem = "strict";
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          CapabilityBoundingSet = "";
          AmbientCapabilities = "";
        };
      };

      honchoDockerfile = pkgs.writeText "honcho-v3.0.12.Dockerfile" ''
        FROM python:3.13-slim-bookworm@sha256:9d7f287598e1a5a978c015ee176d8216435aaf335ed69ac3c38dd1bbb10e8d64
        COPY --from=ghcr.io/astral-sh/uv:0.9.24@sha256:816fdce3387ed2142e37d2e56e1b1b97ccc1ea87731ba199dc8a25c04e4997c5 /uv /bin/uv
        WORKDIR /app
        ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
        RUN --mount=type=cache,target=/root/.cache/uv \
            --mount=type=bind,source=uv.lock,target=uv.lock \
            --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
            uv sync --frozen --no-install-project --no-group dev
        COPY uv.lock pyproject.toml /app/
        RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-group dev
        ENV PATH="/app/.venv/bin:$PATH" HOME=/app UV_CACHE_DIR=/tmp/uv-cache
        RUN addgroup --system app && adduser --system --group app \
            && mkdir -p /tmp/uv-cache \
            && chown -R app:app /app /tmp/uv-cache
        COPY --chown=app:app src/ /app/src/
        COPY --chown=app:app migrations/ /app/migrations/
        COPY --chown=app:app scripts/ /app/scripts/
        COPY --chown=app:app docker/ /app/docker/
        COPY --chown=app:app alembic.ini /app/alembic.ini
        COPY --chown=app:app config.toml* /app/
        USER app
        EXPOSE 8000
      '';

      textModelEnvironment =
        [
          "LLM_OPENAI_API_KEY=local-only"
          "DERIVER_ENABLED=true"
          "DERIVER_MODEL_CONFIG__TRANSPORT=openai"
          "DERIVER_MODEL_CONFIG__MODEL=${nemotronAlias}"
          "DERIVER_MODEL_CONFIG__OVERRIDES__BASE_URL=${containerModelBaseUrl}"
          "DERIVER_MODEL_CONFIG__STRUCTURED_OUTPUT_MODE=json_object"
          "SUMMARY_ENABLED=true"
          "SUMMARY_MODEL_CONFIG__TRANSPORT=openai"
          "SUMMARY_MODEL_CONFIG__MODEL=${nemotronAlias}"
          "SUMMARY_MODEL_CONFIG__OVERRIDES__BASE_URL=${containerModelBaseUrl}"
          "DREAM_ENABLED=true"
          "DREAM_DEDUCTION_MODEL_CONFIG__TRANSPORT=openai"
          "DREAM_DEDUCTION_MODEL_CONFIG__MODEL=${nemotronAlias}"
          "DREAM_DEDUCTION_MODEL_CONFIG__OVERRIDES__BASE_URL=${containerModelBaseUrl}"
          "DREAM_INDUCTION_MODEL_CONFIG__TRANSPORT=openai"
          "DREAM_INDUCTION_MODEL_CONFIG__MODEL=${nemotronAlias}"
          "DREAM_INDUCTION_MODEL_CONFIG__OVERRIDES__BASE_URL=${containerModelBaseUrl}"
        ]
        ++ builtins.concatLists (map
          (level: [
            "DIALECTIC_LEVELS__${level}__MODEL_CONFIG__TRANSPORT=openai"
            "DIALECTIC_LEVELS__${level}__MODEL_CONFIG__MODEL=${nemotronAlias}"
            "DIALECTIC_LEVELS__${level}__MODEL_CONFIG__OVERRIDES__BASE_URL=${containerModelBaseUrl}"
          ])
          [ "minimal" "low" "medium" "high" "max" ]);

      honchoEnvironment = textModelEnvironment ++ [
        "LOG_LEVEL=INFO"
        "PERFORMANCE_LOG_FORMAT=compact"
        "AUTH_USE_AUTH=false"
        "CACHE_ENABLED=true"
        "CACHE_URL=redis://redis:6379/0?suppress=true"
        "DB_CONNECTION_URI=postgresql+psycopg://postgres:${dbPasswordRef}@database:5432/postgres"
        "DB_CONNECT_TIMEOUT_SECONDS=2"
        "EMBED_MESSAGES=true"
        "EMBEDDING_VECTOR_DIMENSIONS=1024"
        "EMBEDDING_MAX_INPUT_TOKENS=8192"
        "EMBEDDING_MODEL_CONFIG__TRANSPORT=openai"
        "EMBEDDING_MODEL_CONFIG__MODEL=${embeddingAlias}"
        "EMBEDDING_MODEL_CONFIG__OVERRIDES__BASE_URL=${containerEmbeddingBaseUrl}"
        "EMBEDDING_MODEL_CONFIG__DIMENSIONS_MODE=never"
        "VECTOR_STORE_TYPE=pgvector"
        "TELEMETRY_ENABLED=false"
        "SENTRY_ENABLED=false"
        "METRICS_ENABLED=false"
        "COLLECT_METRICS_LOCAL=false"
      ];

      appSecurity = {
        read_only = true;
        pull_policy = "never";
        tmpfs = [ "/tmp:size=512m,mode=1777" ];
        cap_drop = [ "ALL" ];
        security_opt = [ "no-new-privileges:true" ];
        extra_hosts = [ "host.docker.internal:host-gateway" ];
        env_file = [ "/var/lib/honcho/runtime.env" ];
        environment = honchoEnvironment;
      };

      composeFormat = pkgs.formats.yaml { };
      composeFile = composeFormat.generate "uwu-honcho-compose.yaml" {
        name = "uwu-honcho";
        networks.default = {
          name = "uwu-honcho";
          driver = "bridge";
          driver_opts."com.docker.network.bridge.name" = "honcho0";
        };
        services = {
          database = {
            image = "pgvector/pgvector:pg15@sha256:a20a57d7aa5217a6af0a391ccf69f4a8512406d6c14be08132f801468cc3cc62";
            restart = "unless-stopped";
            command = [ "postgres" "-c" "max_connections=200" ];
            environment = [
              "POSTGRES_DB=postgres"
              "POSTGRES_USER=postgres"
              "POSTGRES_PASSWORD=${dbPasswordRef}"
              "PGDATA=/var/lib/postgresql/data/pgdata"
            ];
            volumes = [
              "${inputs.honcho}/database/init.sql:/docker-entrypoint-initdb.d/init.sql:ro"
              "pgdata:/var/lib/postgresql/data"
            ];
            healthcheck = {
              test = [ "CMD-SHELL" "pg_isready -U postgres -d postgres" ];
              interval = "5s";
              timeout = "5s";
              retries = 20;
            };
            env_file = [ "/var/lib/honcho/runtime.env" ];
            security_opt = [ "no-new-privileges:true" ];
          };

          redis = {
            image = "redis:8.2@sha256:616bb446d5db225ddf786052834279e7c7222c48694d4451e8af22b8f5953b28";
            restart = "unless-stopped";
            command = [ "redis-server" "--appendonly" "yes" ];
            volumes = [ "redis-data:/data" ];
            healthcheck = {
              test = [ "CMD" "redis-cli" "ping" ];
              interval = "5s";
              timeout = "5s";
              retries = 20;
            };
            # The pinned Redis 8.2.8 image owns /data as 999:999. Running as
            # that identity bypasses its root-only permission/privilege path.
            user = "999:999";
            cap_drop = [ "ALL" ];
            security_opt = [ "no-new-privileges:true" ];
          };

          init = appSecurity // {
            image = honchoImage;
            build = {
              context = toString inputs.honcho;
              dockerfile = toString honchoDockerfile;
            };
            entrypoint = [ "/bin/sh" "-ec" ];
            command = [ "/app/.venv/bin/python scripts/provision_db.py && /app/.venv/bin/python scripts/configure_embeddings.py --yes" ];
            depends_on = {
              database.condition = "service_healthy";
              redis.condition = "service_healthy";
            };
            restart = "no";
          };

          api = appSecurity // {
            image = honchoImage;
            entrypoint = [ "/app/.venv/bin/fastapi" "run" "--host" "0.0.0.0" "src/main.py" ];
            depends_on.init.condition = "service_completed_successfully";
            ports = [ "127.0.0.1:8000:8000" ];
            restart = "unless-stopped";
            healthcheck = {
              test = [
                "CMD"
                "/app/.venv/bin/python"
                "-c"
                "import urllib.request; urllib.request.urlopen('http://localhost:8000/health', timeout=2).read()"
              ];
              interval = "5s";
              timeout = "5s";
              retries = 20;
              start_period = "15s";
            };
          };

          deriver = appSecurity // {
            image = honchoImage;
            entrypoint = [ "/app/.venv/bin/python" "-m" "src.deriver" ];
            depends_on.api.condition = "service_healthy";
            restart = "unless-stopped";
          };
        };
        volumes = {
          pgdata = { };
          redis-data = { };
        };
      };

      hermesLocalConfig = pkgs.writeText "hermes-local-config.yaml" ''
        _config_version: 33
        model:
          default: ${nemotronAlias}
          provider: custom
          base_url: http://127.0.0.1:8080/v1
          api_key: ""
          context_length: 32768
        memory:
          provider: honcho
      '';

      hermesHonchoConfig = pkgs.writeText "hermes-local-honcho.json" (builtins.toJSON {
        enabled = true;
        baseUrl = "http://127.0.0.1:8000";
        environment = "local";
        hosts.hermes_local = {
          enabled = true;
          workspace = "jaide-local";
          peerName = "Jaide";
          aiPeer = "Luna";
          pinUserPeer = true;
          sessionStrategy = "per-session";
          saveMessages = true;
          writeFrequency = "async";
          recallMode = "hybrid";
          contextTokens = 1200;
        };
      });

      installHermesLocalProfile = pkgs.writeShellApplication {
        name = "install-hermes-local-profile";
        runtimeInputs = [ pkgs.coreutils pkgs.hermes-agent ];
        text = ''
          set -euo pipefail
          profile_dir=/home/jaide/.hermes/profiles/local

          if [[ ! -e "$profile_dir/SOUL.md" ]]; then
            if [[ -e "$profile_dir" ]]; then
              printf 'refusing to replace incomplete Hermes profile at %s\n' "$profile_dir" >&2
              exit 1
            fi
            hermes profile create local \
              --no-alias \
              --no-skills \
              --description "Fully local UwU-Server profile: Nemotron + Honcho"
          fi

          install -m 0600 ${lib.escapeShellArg hermesLocalConfig} "$profile_dir/config.yaml"
          install -m 0600 ${lib.escapeShellArg hermesHonchoConfig} "$profile_dir/honcho.json"
        '';
      };

      honchoSetup = pkgs.writeShellApplication {
        name = "setup-local-honcho-runtime";
        runtimeInputs = [ pkgs.coreutils pkgs.openssl ];
        text = ''
          set -euo pipefail
          umask 0077
          state=/var/lib/honcho
          install -d -m 0700 "$state" "$state/backups"
          secret="$state/database-password"
          if [[ ! -s "$secret" ]]; then
            openssl rand -hex 32 > "$secret"
            chmod 0600 "$secret"
          fi
          password=$(<"$secret")
          [[ "$password" =~ ^[0-9a-f]{64}$ ]] || {
            printf 'invalid Honcho database password file\n' >&2
            exit 1
          }
          env_tmp="$state/runtime.env.tmp"
          printf 'HONCHO_DB_PASSWORD=%s\n' "$password" > "$env_tmp"
          chmod 0600 "$env_tmp"
          mv -T "$env_tmp" "$state/runtime.env"
        '';
      };

      waitForModels = pkgs.writeShellApplication {
        name = "wait-for-local-ai-models";
        runtimeInputs = [ pkgs.coreutils pkgs.curl ];
        text = ''
          set -euo pipefail
          for endpoint in http://127.0.0.1:8080/health http://127.0.0.1:8082/health; do
            ready=false
            for _ in $(seq 1 360); do
              if curl --fail --silent --show-error --max-time 3 "$endpoint" >/dev/null; then
                ready=true
                break
              fi
              sleep 5
            done
            [[ "$ready" == true ]] || {
              printf 'timed out waiting for %s\n' "$endpoint" >&2
              exit 1
            }
          done
        '';
      };

      honchoBackup = pkgs.writeShellApplication {
        name = "backup-local-honcho";
        runtimeInputs = [ pkgs.coreutils pkgs.docker-compose pkgs.findutils ];
        text = ''
          set -euo pipefail
          umask 0077
          backup_dir=/var/lib/honcho/backups
          install -d -m 0700 "$backup_dir"
          stamp=$(date -u +%Y%m%dT%H%M%SZ)
          partial="$backup_dir/honcho-$stamp.dump.partial"
          final="$backup_dir/honcho-$stamp.dump"
          trap 'rm -f "$partial"' EXIT
          docker-compose \
            --project-name uwu-honcho \
            --file ${lib.escapeShellArg composeFile} \
            --env-file /var/lib/honcho/runtime.env \
            exec -T database pg_dump --username=postgres --dbname=postgres --format=custom > "$partial"
          [[ -s "$partial" ]]
          mv -T "$partial" "$final"
          trap - EXIT
          find "$backup_dir" -maxdepth 1 -type f -name 'honcho-*.dump' -mtime +14 -delete
          printf 'Honcho backup: %s\n' "$final"
        '';
      };
    in
    {
      assertions = [
        {
          assertion = inputs.honcho.rev == honchoCommit;
          message = "Honcho source input revision must match the reviewed honchoCommit";
        }
        {
          assertion = !(builtins.elem "docker" config.users.users.jaide.extraGroups);
          message = "Jaide must not be added to the root-equivalent docker group";
        }
      ];

      virtualisation.docker = {
        enable = true;
        autoPrune = {
          enable = true;
          dates = "weekly";
          flags = [ "--filter=until=336h" ];
        };
      };

      users.groups.local-ai = { };
      users.users.local-ai = {
        isSystemUser = true;
        group = "local-ai";
        extraGroups = [ "render" "video" ];
        home = "/var/lib/local-ai";
        createHome = false;
      };

      environment.systemPackages = [
        pkgs.llama-cpp-vulkan
        honchoBackup
      ];

      networking.firewall.interfaces.honcho0.allowedTCPPorts = [ 8080 8082 ];

      # ReadWritePaths requires its target to exist before systemd constructs
      # the service namespace. Create only the managed profile roots; Jaide
      # still owns the files and the rest of ~/.hermes.
      systemd.tmpfiles.rules = [
        "d /home/jaide/.hermes 0700 jaide users -"
        "d /home/jaide/.hermes/profiles 0700 jaide users -"
      ];

      systemd.services = {
        local-ai-models = {
          description = "Download and verify local AI model artifacts";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            Restart = "on-failure";
            RestartSec = "30s";
            User = "local-ai";
            Group = "local-ai";
            StateDirectory = "local-ai";
            StateDirectoryMode = "0750";
            ExecStart = lib.getExe modelDownloader;
            TimeoutStartSec = "2h";
            UMask = "0027";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectSystem = "strict";
            # aria2 uses c-ares, which needs AF_NETLINK to discover usable
            # interfaces before resolving the pinned Hugging Face URLs.
            RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_NETLINK" "AF_UNIX" ];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            LockPersonality = true;
            CapabilityBoundingSet = "";
            AmbientCapabilities = "";
          };
        };

        nemotron-local = lib.recursiveUpdate commonLlamaService {
          description = "Local Nemotron 3 Nano 30B-A3B OpenAI API";
          serviceConfig.ExecStart = lib.escapeShellArgs [
            "${pkgs.llama-cpp-vulkan}/bin/llama-server"
            "--model"
            "${modelDirectory}/${nemotronFile}"
            "--alias"
            nemotronAlias
            "--host"
            "0.0.0.0"
            "--port"
            "8080"
            "--ctx-size"
            "32768"
            "--temp"
            "0.6"
            "--top-p"
            "0.95"
            "--min-p"
            "0.01"
            # Unsloth suggests --prio 3, but llama.cpp maps that to
            # SCHED_FIFO/90. Keep RestrictRealtime rather than allowing local
            # inference to starve SSH and system services.
            "--jinja"
            "--special"
            "--flash-attn"
            "on"
            "--n-gpu-layers"
            "999"
          ];
        };

        qwen-embedding-local = lib.recursiveUpdate commonLlamaService {
          description = "Local Qwen3 0.6B embedding OpenAI API";
          serviceConfig.ExecStart = lib.escapeShellArgs [
            "${pkgs.llama-cpp-vulkan}/bin/llama-server"
            "--model"
            "${modelDirectory}/${embeddingFile}"
            "--alias"
            embeddingAlias
            "--host"
            "0.0.0.0"
            "--port"
            "8082"
            "--ctx-size"
            "8192"
            "--batch-size"
            "8192"
            "--ubatch-size"
            "2048"
            "--embedding"
            "--pooling"
            "last"
            "--flash-attn"
            "on"
            "--n-gpu-layers"
            "999"
          ];
        };

        hermes-local-profile = {
          description = "Install the managed local-only Hermes profile";
          wantedBy = [ "multi-user.target" ];
          before = [ "honcho-local.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "jaide";
            Group = "users";
            Environment = "HOME=/home/jaide";
            ExecStart = lib.getExe installHermesLocalProfile;
            UMask = "0077";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = "read-only";
            ReadWritePaths = [ "/home/jaide/.hermes" ];
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            ProtectClock = true;
            RestrictSUIDSGID = true;
            LockPersonality = true;
            RestrictRealtime = true;
            RestrictNamespaces = true;
            CapabilityBoundingSet = "";
            AmbientCapabilities = "";
            RestrictAddressFamilies = [ "AF_UNIX" ];
          };
        };

        honcho-local = {
          description = "Fully local Honcho v3 memory service";
          after = [
            "docker.service"
            "nemotron-local.service"
            "qwen-embedding-local.service"
          ];
          requires = [
            "docker.service"
            "nemotron-local.service"
            "qwen-embedding-local.service"
          ];
          wantedBy = [ "multi-user.target" ];
          path = [ pkgs.docker pkgs.docker-buildx pkgs.docker-compose ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StateDirectory = "honcho";
            StateDirectoryMode = "0700";
            ExecStartPre = [
              (lib.getExe honchoSetup)
              (lib.getExe waitForModels)
              (lib.escapeShellArgs [
                "${pkgs.docker}/bin/docker"
                "buildx"
                "build"
                "--builder"
                "default"
                "--load"
                "--file"
                (toString honchoDockerfile)
                "--tag"
                honchoImage
                (toString inputs.honcho)
              ])
            ];
            ExecStart = lib.escapeShellArgs [
              "${pkgs.docker-compose}/bin/docker-compose"
              "--project-name"
              "uwu-honcho"
              "--file"
              (toString composeFile)
              "--env-file"
              "/var/lib/honcho/runtime.env"
              "up"
              "--detach"
              "--no-build"
              "--remove-orphans"
              "--wait"
            ];
            ExecStop = lib.escapeShellArgs [
              "${pkgs.docker-compose}/bin/docker-compose"
              "--project-name"
              "uwu-honcho"
              "--file"
              (toString composeFile)
              "--env-file"
              "/var/lib/honcho/runtime.env"
              "down"
              "--remove-orphans"
            ];
            TimeoutStartSec = "45min";
            TimeoutStopSec = "5min";
          };
        };

        honcho-backup = {
          description = "Atomic local PostgreSQL backup for Honcho";
          after = [ "honcho-local.service" ];
          requires = [ "honcho-local.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe honchoBackup;
            UMask = "0077";
            Nice = 10;
            IOSchedulingClass = "best-effort";
            IOSchedulingPriority = 7;
          };
        };
      };

      systemd.timers.honcho-backup = {
        description = "Daily Honcho database backup";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          RandomizedDelaySec = "30m";
          Persistent = true;
          Unit = "honcho-backup.service";
        };
      };
    }
  ;
}
