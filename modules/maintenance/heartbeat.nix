# Heartbeat — dead-man's-switch ping to Uptime Kuma.
#
# This module is the CONFIG-ONLY contributor to `nixos.modules.maintenance`
# for heartbeat functionality. All NixOS option declarations live in
# `modules/maintenance/default.nix` (the umbrella). This split mirrors
# the disko convention: `disko.nix` declares options, `btrfs-dedup.nix`
# contributes config only. flake-parts merges all files under
# `nixos.modules.maintenance` into a single deferred module, which
# the NixOS module system then processes on each host that imports
# the role.
#
# ## Why config-only here
#
# flake-parts evaluates each `nixos.modules.<key>` deferred module at
# flake-time when processing the flake outputs. At that point, the
# module function only has `lib` and `inputs` in scope — reading
# `config.sops.placeholder.<key>` or `config.<NixOS-option>` fails.
# The clean fix is for the function to take only `{ pkgs, lib, ... }:`
# (no `config`), and contribute config without reading options. The
# umbrella declares options; the NixOS module system wires everything
# at host eval time.
#
# The trade-off: this file hardcodes `5min` as the heartbeat interval
# rather than reading `config.maintenance.heartbeat.intervalSeconds`.
# Hosts that need a different interval can override the timer unit
# directly via `systemd.timers.heartbeat.timerConfig.OnUnitActiveSec`
# in their host module (after this module's contribution), or by
# redefining the timer via an `mkForce` override.
#
# ## Per-host wiring
#
# Each host that wants heartbeats imports the maintenance role:
#
#   config.nixos.modules.maintenance  # in modules = [ ... ]
#
# And declares a sops secret with the Uptime Kuma push URL:
#
#   sops.secrets.heartbeat_endpoint = {
#     sopsFile = ...;
#     mode = "0400";
#   };
#
# The sops secret is a single-line file containing the full URL:
#   https://status.jaidechan.moe/api/push/<uuid>?status=up&msg=OK
#
# ## Behaviour
#
# The heartbeat script does an HTTP HEAD on the URL. Uptime Kuma's
# push endpoint accepts GET, HEAD, and POST — HEAD is the cheapest.
# We rewrite the URL's `&msg=` query parameter on each ping to
# include the current ISO timestamp so you can see "last ping at
# <ts>" in Uptime Kuma's heartbeat panel.
#
# If the sops secret is missing (host deployed before secret was
# populated) the service silently no-ops with a "no endpoint"
# warning. Non-fatal.
{ pkgs, ... }:
{
  systemd.services.heartbeat = {
    description = "Heartbeat ping to Uptime Kuma (dead-man's switch)";
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "heartbeat";
    };
    script = ''
      # sops-nix renders `sops.secrets.heartbeat_endpoint` to
      # /run/secrets/heartbeat-endpoint. The umbrella declares
      # `sopsKey` defaulting to "heartbeat_endpoint" — same file.
      endpoint_file="/run/secrets/heartbeat-endpoint"
      if [ ! -f "$endpoint_file" ]; then
        echo "heartbeat: no endpoint configured at $endpoint_file — skipping ping"
        exit 0
      fi
      endpoint=$(cat "$endpoint_file" | tr -d '[:space:]')
      if [ -z "$endpoint" ]; then
        echo "heartbeat: endpoint file is empty — skipping ping"
        exit 0
      fi
      ts=$(date -u +%FT%TZ)
      case "$endpoint" in
        *"&msg="*) url="''${endpoint/&msg=*/\&msg=ping-$ts}" ;;
        *) url="$endpoint&msg=ping-$ts" ;;
      esac
      if ! ${pkgs.curl}/bin/curl --silent --show-error --fail --max-time 10 \
          -X HEAD "$url"; then
        echo "heartbeat: ping to Uptime Kuma failed (exit $?) — will retry next tick"
        exit 1
      fi
    '';
  };

  systemd.timers.heartbeat = {
    description = "Periodic heartbeat ping to Uptime Kuma";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Hardcoded to 5min — see module header for override path.
      # Hosts that need different cadences can `mkForce` the timer
      # in their host module.
      OnUnitActiveSec = "5min";
      # Don't run immediately after boot — give UwU-Server / Uptime
      # Kuma a chance to come up first. Spread retries across the
      # fleet with a small random delay so they don't ping in lockstep.
      RandomizedDelaySec = "60s";
      Persistent = true;
    };
  };
}