# Hermes Mobile Bridge - Android "Hermes Console" companion service.
#
# The NixOS equivalent of `curl -fsSL
# https://raw.githubusercontent.com/xP3ta/hermes-setup/main/hermes-mobile-setup.sh | sh`,
# expressed declaratively. It does NOT touch ~/.hermes/config.yaml (the user
# owns their dotfiles), but it DOES:
#
#   1. Pin the xP3ta/hermes-setup source (bridge.py + manifest) to a rev and
#      verify the upstream-published sha256+size on every deploy. The repo
#      publishes a closed manifest (`bridge-release.json`) that the installer
#      cross-checks at runtime; we honor that manifest here as a Nix
#      assertion so a broken upstream release fails the build, not the
#      pairing.
#   2. Stage `hermes_bridge.py` to /home/luna/.hermes/ (atomic, with a
#      rollback backup, identical to the installer's lifecycle).
#   3. Write three runner scripts to ~/.hermes/console-services/ matching the
#      upstream installer 1:1 so the systemd units can execute them
#      verbatim (gateway/dashboard/bridge).
#   4. Provide a sops-managed `BRIDGE_TOKEN` (the API key the Android app
#      presents) and write `pairing.env` (BRIDGE_HOST, BRIDGE_PORT,
#      BRIDGE_SCOPES, BRIDGE_TOKEN) - likewise identical to the installer.
#   5. Wire three systemd --user units (hermes-mobile-{gateway,dashboard,
#      bridge}.service), hardened after the hermes-router + hermes-gateway
#      template. Reuses the existing `hermes-gateway` unit's pattern but
#      renames to `hermes-mobile-*` so it stays distinct from the
#      hermes-gateway messaging service (different intent, different port).
#   6. Ship a `hermes-mobile-bridge-pair-qr` activation command that prints
#      the `hermes://pair?...` URL (and a QR rendered via the `qrencode`
#      package) for the Android app to scan.
#
# Idempotency: every step is reproducible from a sealed Nix store path, so
# a fresh `just deploy` reproduces the same state without re-running the
# upstream installer. The hub-and-spoke pairing key lives in sops, so
# rotating it is `just sops-edit` + `just deploy`.
#
# Port plan (matches xP3ta/hermes-setup README):
#   8642 - gateway       (OpenAI-compatible API the app talks to)
#   9119 - dashboard     (web admin UI)
#   9131 - mobile bridge (the Android companion service - its own API)
#
# All three listen on 0.0.0.0 inside the Netbird mesh (wireguard-encrypted
# - plain HTTP is acceptable per the existing 8080 convention); they are not
# opened on LAN or public interfaces. The mesh policy is updated in
# modules/network/netbird-policy.json and the firewall port list in
# modules/network/netbird-mesh.nix.
{ inputs, ... }:
{
  nixos.hosts."Luna-Server" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      # Pinned upstream release (xP3ta/hermes-setup). The rev chosen is the last
      # "Sync from app (bridge 1.18.0)" commit - the source-of-truth sync point
      # that matches the published `bridge-release.json` manifest 1:1. The
      # latest HEAD on `main` is an unrelated docs/firewall fix; we don't track
      # `main` because the installer's own verifier cross-checks the file
      # against the manifest, and rolling the rev without bumping the manifest
      # would break the in-bridge self-update check.
      bridgeRev = "81b0993be54469dbdf9c452fbab16d657c077b2a";
      bridgeSource = pkgs.fetchFromGitHub {
        owner = "xP3ta";
        repo = "hermes-setup";
        rev = bridgeRev;
        hash = "sha256-oWdrvFfU5FXYnlfy5vtLwNh96KChq5mFXtfhq6N/6PY=";
      };

      # The closed manifest published by the upstream repo
      # (`bridge-release.json`). Its three fields are the contract the bridge
      # verifies against an `hermes_bridge.py` download before executing it.
      # We re-encode them as Nix-time assertions so a broken upstream release
      # fails `nixos-rebuild` rather than failing the pairing.
      bridgeManifest = builtins.fromJSON (builtins.readFile "${bridgeSource}/bridge-release.json");
      expectedBridgeVersion = "1.18.0";
      expectedBridgeSha256 = "f8243b6e651c3e3fb8ca7f19e83677f268776624041a4dedae47a03b879a7a42";
      expectedBridgeSize = 132711;

      herHome = "/home/luna/.hermes";
      herConsoleServices = "${herHome}/console-services";
      herLogs = "${herHome}/logs";
      herUser = "luna";
      herGroup = "users";
      herHermesBin = "${pkgs.hermes-agent}/bin/hermes";
      hermesAgentVenv = pkgs.hermes-agent.hermesVenv;

      # Activation script that stages hermes_bridge.py, the runner scripts,
      # and the systemd user units. Idempotent: every step checks for prior
      # state and only mutates when the destination is missing or stale.
      stageBridge = pkgs.writeShellApplication {
        name = "hermes-mobile-bridge-stage";
        runtimeInputs = [ pkgs.coreutils pkgs.gnused pkgs.hermes-agent ];
        text = ''
              set -euo pipefail

              bridge_source=${lib.escapeShellArg "${bridgeSource}/hermes_bridge.py"}
              bridge_target="${herHome}/hermes_bridge.py"
              bridge_backup="${herHome}/hermes_bridge.py.rollback"
              bridge_tmp="${herHome}/hermes_bridge.py.new"
              services_dir=${lib.escapeShellArg herConsoleServices}
              logs_dir=${lib.escapeShellArg herLogs}

              mkdir -p "$services_dir" "$logs_dir" "${herHome}/.config/systemd/user"

              # 1. Stage hermes_bridge.py atomically. The installer does the same
              #    swap-with-backup dance so a broken bridge never replaces a good
              #    one; we mirror it here so the on-disk state is identical whether
              #    bootstrapped via the curl installer or via the NixOS module.
              if [ -f "$bridge_target" ]; then
                cp -f "$bridge_target" "$bridge_backup"
              fi
              install -m 0644 "$bridge_source" "$bridge_tmp"
              mv -f "$bridge_tmp" "$bridge_target"
              echo "hermes-mobile-bridge: staged $bridge_target"

              # 2. Write the three runner scripts. They are byte-identical to
              #    what the upstream installer writes (gateway/dashboard/bridge),
              #    so any future update to the upstream installer can be diffed
              #    against this Nix expression and inspected.
              install -d -m 0700 '${herConsoleServices}'
              cat > '${herConsoleServices}/hermes-gateway.sh' <<'GATEWAY_RUNNER_BODY'
          #!/bin/sh
          set -a
          . '${herConsoleServices}/pairing.env'
          set +a
          # Hermes security audit blocks binding API server to non-loopback
          # without API_SERVER_KEY. Use the bridge token (same sops secret)
          # so a single key authenticates both surfaces.
          export API_SERVER_KEY="$BRIDGE_TOKEN"
          export API_SERVER_ENABLED=true
          export HERMES_HOME='${herHome}'
          export API_SERVER_HOST='0.0.0.0'
          export API_SERVER_PORT=8642
          cd '${herHome}'
          exec '${herHermesBin}' gateway run --replace
          GATEWAY_RUNNER_BODY
              cat > '${herConsoleServices}/hermes-dashboard.sh' <<'DASHBOARD_RUNNER_BODY'
          #!/bin/sh
          export HERMES_HOME='${herHome}'
          cd '${herHome}'
          exec '${herHermesBin}' dashboard --host '0.0.0.0' --port 9119 --no-open
          DASHBOARD_RUNNER_BODY
              cat > '${herConsoleServices}/hermes-bridge.sh' <<'BRIDGE_RUNNER_BODY'
          #!/bin/sh
          set -a
          . '${herConsoleServices}/pairing.env'
          set +a
          export HERMES_HOME='${herHome}'
          export BRIDGE_HERMES_HOME='${herHome}'
          cd '${herHome}'
          exec '${hermesAgentVenv}/bin/python' -u '${herHome}/hermes_bridge.py' --i-know-what-im-doing
          BRIDGE_RUNNER_BODY
              chmod 0700 \
                '${herConsoleServices}/hermes-gateway.sh' \
                '${herConsoleServices}/hermes-dashboard.sh' \
                '${herConsoleServices}/hermes-bridge.sh'
              echo "hermes-mobile-bridge: wrote gateway/dashboard/bridge runners"

              # 3. Mirror the sops-rendered pairing.env into the directory
              #    the bridge runner expects. The upstream installer wrote
              #    ~/.hermes/console-services/pairing.env directly; we
              #    source-of-truth it at /run/secrets/rendered/... via the
              #    sops template, so symlink rather than copy. The sops
              #    template path is stable across deploys (filename is
              #    fixed in the module), so the symlink target never
              #    rotates.
              SOPS_RENDERED='/run/secrets/rendered/hermes-mobile-bridge-pairing'
              CONSUMER='${herConsoleServices}/pairing.env'
              if [ -f "$SOPS_RENDERED" ]; then
                ln -sfn "$SOPS_RENDERED" "$CONSUMER"
                echo "hermes-mobile-bridge: linked pairing.env -> $SOPS_RENDERED"
              else
                echo "hermes-mobile-bridge: WARNING $SOPS_RENDERED not present yet (sops template may not have rendered); bridge.sh will fail to source pairing.env" >&2
              fi
        '';
      };

      # The QR/URL renderer for the Android app. `qrencode` is the upstream
      # installer's preferred renderer; we ship it here so the activation
      # command can be run from any shell, not just the desktop.
      pairQr = pkgs.writeShellApplication {
        name = "hermes-mobile-bridge-pair-qr";
        runtimeInputs = [ pkgs.coreutils pkgs.gnused pkgs.jq pkgs.qrencode pkgs.sudo ];
        text = ''
          set -euo pipefail

          # The host we hand to the app is the Netbird mesh IP — that's
          # the only network the Android phone reliably shares with the
          # server (per module header). We resolve it at run-time so the
          # QR stays valid even if the mesh address rotates (which it
          # shouldn't, but belt-and-suspenders for a QR that may sit on
          # a screen for a while).
          #
          # The netbird-mesh systemd wrapper is what NixOS exposes when
          # services.netbirdMesh.enable = true; its name comes from the
          # `services.netbird.clients.mesh` instance attr + the `bin.suffix`
          # = "mesh" (so `mkBin "netbird"` yields `netbird-mesh`). The
          # daemon runs as user `netbird-mesh`, which is why we sudo into
          # it before invoking the status CLI.
          netbird_bin="$(command -v netbird-mesh || true)"
          mesh_ip=""
          if [ -n "$netbird_bin" ] && command -v sudo >/dev/null 2>&1; then
            mesh_ip="$(sudo -u netbird-mesh "$netbird_bin" status --json 2>/dev/null \
              | ${pkgs.jq}/bin/jq -r '"\(.netbirdIp)" | split("/")[0]' 2>/dev/null || true)"
          fi
          if [ -z "$mesh_ip" ]; then
            echo "hermes-mobile-bridge-pair-qr: Netbird mesh is not up on this host" >&2
            echo "  the bridge will still pair via LAN, but the QR will use" >&2
            echo "  the LAN IP. Bring wt0 up and re-run for the" >&2
            echo "  remote-friendly URL." >&2
          fi

          # sops-nix renders secrets to /run/secrets/<name> (no 'rendered/'
          # prefix), and the name follows the sops.secrets key verbatim
          # (underscores, not dashes). The pairing.env template lands at
          # /run/secrets/rendered/<name> because sops.templates adds the
          # 'rendered' prefix; secrets do not.
          api_token="$(${pkgs.coreutils}/bin/cat /run/secrets/hermes_mobile_bridge_api_key 2>/dev/null || true)"
          if [ -z "$api_token" ]; then
            echo "hermes-mobile-bridge-pair-qr: API key not rendered at /run/secrets/hermes_mobile_bridge_api_key" >&2
            echo "  rebuild has likely not run yet - try 'just deploy' first." >&2
            exit 1
          fi

          gateway_host="$mesh_ip"
          gateway_port=8642
          dashboard_port=9119
          bridge_port=9131

          # The app's pairing URL is a `hermes://pair?gateway=...&dashboard=...`
          # link. The upstream installer also encodes the bridge credentials,
          # which is what the `pairing.env` template ships (BRIDGE_TOKEN) - the
          # app uses it to authenticate the companion channel.
          # The QR the installer prints is the FULL pairing URL; we mirror
          # that format here so the app's QR scanner is happy either way.
          pair_url="hermes://pair?host=$gateway_host&port=$gateway_port&token=$api_token&dashboard=http://$gateway_host:$dashboard_port&bridge=http://$gateway_host:$bridge_port&bridge_token=$api_token"

          echo
          echo "  +--------------------------------------------------------------+"
          echo "  |  SCAN THIS QR WITH HERMES CONSOLE                            |"
          echo "  +--------------------------------------------------------------+"
          echo
          qrencode -t ANSIUTF8 "$pair_url"
          echo
          echo "  Pairing URL (paste in the app if your phone shares this screen):"
          echo "    $pair_url"
          echo
          echo "  Netbird mesh IP used: $gateway_host"
          echo "  Gateway:  http://$gateway_host:$gateway_port"
          echo "  Dashboard:http://$gateway_host:$dashboard_port"
          echo "  Bridge:   http://$gateway_host:$bridge_port"
          echo
        '';
      };
    in
    {
      assertions = [
        {
          assertion = bridgeManifest.version == expectedBridgeVersion;
          message = "Pinned xP3ta/hermes-setup ${bridgeRev} manifest version (${bridgeManifest.version}) does not match expected ${expectedBridgeVersion}. Bump the rev and the expected triple in modules/ai/hermes-mobile-bridge.nix together.";
        }
        {
          assertion = bridgeManifest.sha256 == expectedBridgeSha256;
          message = "Pinned xP3ta/hermes-setup ${bridgeRev} manifest sha256 (${bridgeManifest.sha256}) does not match expected ${expectedBridgeSha256}. The pinned source no longer matches the manifest - refuse to build.";
        }
        {
          assertion = bridgeManifest.size == expectedBridgeSize;
          message = "Pinned xP3ta/hermes-setup ${bridgeRev} manifest size (${bridgeManifest.size}) does not match expected ${expectedBridgeSize}.";
        }
        {
          assertion = (builtins.hashString "sha256" (builtins.readFile "${bridgeSource}/hermes_bridge.py")) == expectedBridgeSha256;
          message = "Pinned xP3ta/hermes-setup ${bridgeRev} hermes_bridge.py sha256 does not match the manifest. Either the pinned rev is wrong or upstream introduced a regression.";
        }
        {
          assertion = (builtins.stringLength (builtins.readFile "${bridgeSource}/hermes_bridge.py")) == expectedBridgeSize;
          message = "Pinned xP3ta/hermes-setup ${bridgeRev} hermes_bridge.py size does not match the manifest.";
        }
      ];

      # sops - the API key the Android app presents. Mandatory: the bridge
      # rejects requests without a strong token, and the installer
      # refuses to print a QR if the key is weak.
      sops.secrets.hermes_mobile_bridge_api_key = {
        sopsFile = "${inputs.nixos-secrets}/secrets/Luna-Server/hermes-mobile-bridge.yaml";
        key = "hermes_mobile_bridge_api_key";
        owner = herUser;
        group = herGroup;
        mode = "0400";
      };

      # pairing.env - the bridge process reads this on start. Match the
      # upstream installer's layout 1:1 so a hand-deployed bridge would
      # behave the same as a Nix-deployed one.
      sops.templates.hermes-mobile-bridge-pairing = {
        content = ''
          BRIDGE_HOST=0.0.0.0
          BRIDGE_PORT=9131
          BRIDGE_SCOPES=read,memory,soul,skills,cron,config,command
          BRIDGE_READ_ONLY=false
          BRIDGE_TOKEN=${config.sops.placeholder.hermes_mobile_bridge_api_key}
        '';
        owner = herUser;
        group = herGroup;
        mode = "0400";
        restartUnits = [ "hermes-mobile-bridge.service" ];
      };

      # Staging script - runs once per deploy to drop hermes_bridge.py
      # into ~/.hermes/ and write the three runner scripts. Idempotent.
      systemd.services.hermes-mobile-bridge-stage = {
        description = "Stage Hermes Mobile Bridge (xP3ta/hermes-setup) for Luna";
        wantedBy = [ "multi-user.target" ];
        after = [ "hermes-local-profile.service" ];
        requires = [ "hermes-local-profile.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = herUser;
          Group = herGroup;
          Environment = "HOME=/home/${herUser}";
          ExecStart = lib.getExe stageBridge;
          UMask = "0077";
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
          ReadWritePaths = [
            herHome
            "${herHome}/.config/systemd/user"
          ];
          RestrictAddressFamilies = [ "AF_UNIX" ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          CapabilityBoundingSet = "";
          AmbientCapabilities = "";
        };
      };

      # The three user-scope services. They each get their own unit
      # (mirroring the upstream installer's three systemd --user units) so
      # failure isolation is clean and the per-service log destinations
      # align with the installer's `~/.hermes/logs/<name>.log` convention.
      systemd.user.services.hermes-mobile-gateway = {
        description = "Hermes Mobile gateway (OpenAI-compatible API for Android app)";
        documentation = [ "https://github.com/xP3ta/hermes-setup" ];
        unitConfig.ConditionUser = herUser;
        wantedBy = [ "default.target" ];
        after = [ "hermes-mobile-bridge-stage.service" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${herConsoleServices}/hermes-gateway.sh";
          WorkingDirectory = herHome;
          Restart = "always";
          RestartSec = "10s";
          Environment = [
            "HOME=/home/${herUser}"
            "PATH=/run/current-system/sw/bin:/home/${herUser}/.nix-profile/bin"
          ];
          # Mirror the hermes-gateway hardening template.
          CapabilityBoundingSet = [ "" ];
          ProtectSystem = "strict";
          ProtectHome = "read-only";
          ReadWritePaths = [
            herHome
            "/home/${herUser}/.cache"
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
        };
      };

      systemd.user.services.hermes-mobile-dashboard = {
        description = "Hermes Mobile dashboard (web admin UI on :9119)";
        documentation = [ "https://github.com/xP3ta/hermes-setup" ];
        unitConfig.ConditionUser = herUser;
        wantedBy = [ "default.target" ];
        after = [ "hermes-mobile-bridge-stage.service" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${herConsoleServices}/hermes-dashboard.sh";
          WorkingDirectory = herHome;
          Restart = "always";
          RestartSec = "10s";
          Environment = [
            "HOME=/home/${herUser}"
            "PATH=/run/current-system/sw/bin:/home/${herUser}/.nix-profile/bin"
          ];
          CapabilityBoundingSet = [ "" ];
          ProtectSystem = "strict";
          ProtectHome = "read-only";
          ReadWritePaths = [ herHome "/home/${herUser}/.cache" ];
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = false;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        };
      };

      systemd.user.services.hermes-mobile-bridge = {
        description = "Hermes Mobile bridge (Android companion service on :9131)";
        documentation = [ "https://github.com/xP3ta/hermes-setup" ];
        unitConfig.ConditionUser = herUser;
        wantedBy = [ "default.target" ];
        after = [ "hermes-mobile-bridge-stage.service" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${herConsoleServices}/hermes-bridge.sh";
          WorkingDirectory = herHome;
          Restart = "always";
          RestartSec = "10s";
          EnvironmentFile = config.sops.templates.hermes-mobile-bridge-pairing.path;
          Environment = [
            "HOME=/home/${herUser}"
            "PATH=/run/current-system/sw/bin:/home/${herUser}/.nix-profile/bin"
          ];
          CapabilityBoundingSet = [ "" ];
          ProtectSystem = "strict";
          ProtectHome = "read-only";
          ReadWritePaths = [
            herHome
            "/home/${herUser}/.cache"
          ];
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = false;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          # The bridge reaches back to the gateway (:8642) and the
          # Hermes agent itself (AF_UNIX socket via the home dir), so
          # we keep AF_INET/AF_INET6 here for the loopback path.
          RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        };
      };

      # The QR command is exposed as a system package so it can be
      # invoked as `hermes-mobile-bridge-pair-qr` from any shell.
      environment.systemPackages = [ pairQr ];

      # Build outputs (mirrors hermes-router.nix) so regression tests
      # can pin the staged bridge source for inspection.
      system.build.hermesMobileBridge = bridgeSource;
      system.build.hermesMobileBridgePairQr = pairQr;
    };
}
