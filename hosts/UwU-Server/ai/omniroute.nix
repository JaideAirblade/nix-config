# OmniRoute — Docker-backed OpenAI-compatible router that runs alongside
# the existing Hermes Router. Pinned image lives in `pkgs/omniroute`;
# this module only declares how it runs on UwU-Server.
#
# IMPORTANT: `hermes-router.service` stays enabled for the entire
# lifetime of this module. We use port 8320 here for staged smoke
# tests; the cutover to 8319 happens in a separate commit, only
# after live-verify of all four OpenAI-compatible routes against
# OmniRoute on 8320 succeeds. See `tests/server-omniroute-regressions.py`
# for the assertions that enforce the "no premature 8319 takeover"
# contract.
{ inputs, ... }:
{
  nixos.hosts."UwU-Server" =
    { config, lib, pkgs, ... }:

    {
      # Reuse the existing proxy key from sops. No new sops entries
      # are added; the same value is published as both ROUTER_API_KEY
      # (for any process that still resolves that env var, e.g. the
      # installed Mnemosyne hermes-agent) and OMNIROUTE_API_KEY
      # (consumed by OmniRoute's persistent-env-var auth passthrough
      # at /tmp/OmniRoute-inspect/src/sse/services/auth.ts:2482).
      sops.secrets.omniroute_api_key = {
        sopsFile = "${inputs.nixos-secrets}/secrets/UwU-Server/hermes-router.yaml";
        key = "hermes_router_proxy_api_key";
        owner = "omniroute";
        group = "users";
        mode = "0400";
      };

      sops.templates.omniroute-env = {
        content = ''
          OMNIROUTE_API_KEY=${config.sops.placeholder.omniroute_api_key}
          ROUTER_API_KEY=${config.sops.placeholder.omniroute_api_key}
          REQUIRE_API_KEY=true
          HOST=127.0.0.1
          HOSTNAME=127.0.0.1
          PORT=8320
          DASHBOARD_PORT=8320
          API_PORT=8320
          DATA_DIR=/app/data
          # OmniRoute's strict env validator requires the literal
          # strings "true"/"false" for boolean toggles, not 1/0.
          OMNIROUTE_NO_UPDATE_NOTIFIER=true
          OMNIROUTE_DISABLE_BACKGROUND_SERVICES=true
        '';
        owner = "omniroute";
        group = "users";
        mode = "0400";
        restartUnits = [ "omniroute-container.service" ];
      };

      users.users.omniroute = {
        isSystemUser = true;
        group = "users";
        home = "/var/lib/omniroute";
        createHome = true;
      };
      systemd.tmpfiles.rules = [
        "d /var/lib/omniroute 0750 omniroute users - -"
      ];

      # The unit mirrors the existing Honcho container-supervisor
      # pattern (`modules/ai/honcho.nix:honcho-local`). It runs as
      # root because the docker CLI needs `/root/.docker/config.json`
      # and the docker socket, and the inner container is already
      # sandboxed by Docker's own user-namespace + the `--user 984:100`
      # mapping we apply below. The DATA_DIR bind mount is owned by
      # the same UID/GID the container runs as, so the image's
      # bootstrap-secret persistence works without an EACCES.
      systemd.services.omniroute-container = {
        description = "OmniRoute OpenAI-compatible AI router (container)";
        after = [ "docker.service" "network-online.target" ];
        wants = [ "docker.service" "network-online.target" ];
        # Auto-start on boot so OmniRoute is reachable on 127.0.0.1:8320
        # without manual intervention. Hermes Router stays enabled and
        # primary on 127.0.0.1:8319 — OmniRoute is a parallel router,
        # not a replacement. The cutover to 8319 happens in a separate
        # commit only after live-verify of all four OpenAI-compatible
        # routes against OmniRoute on 8320 succeeds.
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.docker ];
        serviceConfig = {
          Type = "exec";
          User = "root";
          Group = "root";
          # Remove any stale container with the same name from a
          # previous start (e.g. if it was killed before ExecStopPost).
          # `docker run` without `--rm` will refuse to start if the
          # name is taken, so this is the deterministic recovery path.
          ExecStartPre = lib.escapeShellArgs [
            "${pkgs.docker}/bin/docker" "rm" "-f" "omniroute"
          ];
          ExecStart = lib.escapeShellArgs [
            "${pkgs.docker}/bin/docker"
            "run"
            "--rm"
            "--name" "omniroute"
            "--user" "984:100"
            "--env-file" config.sops.templates.omniroute-env.path
            "-v" "/var/lib/omniroute:/app/data"
            "-p" "127.0.0.1:8320:8320"
            "--label" "uwu-server.role=omniroute"
            "diegosouzapw/omniroute@sha256:92c768c56e2de32c51a0621ef182835018b00b288c9bb235c5c5e4514658c1a1"
          ];
          ExecStop = "-${pkgs.docker}/bin/docker stop omniroute";
          ExecStopPost = "-${pkgs.docker}/bin/docker rm -f omniroute";
          Restart = "on-failure";
          RestartSec = "10s";
          TimeoutStartSec = "120s";
          TimeoutStopSec = "30s";
          UMask = "0077";
        };
      };
    };
}
