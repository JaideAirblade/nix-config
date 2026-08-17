# Heartbeat — dead-man's-switch ping to Uptime Kuma.
#
# Pure NixOS module (no `nixos.modules.maintenance = ...` wrapper).
# Hosts import it directly into their `modules = [ ... ]` list:
#
#   ./../../modules/maintenance/heartbeat.nix
#
# ## Why pure NixOS module shape (no dendritic role wrapper)
#
# flake-parts evaluates all `imports = [ ... ]` as NixOS modules.
# When a module's top-level return value is
# `{ nixos.modules.maintenance = <function> }`, flake-parts errors
# with `error: The option 'nixos' does not exist` because `nixos`
# isn't in flake-parts's top-level option set. The `nixos.modules.X`
# wrapper only works for files auto-imported by the dendritic walker
# (where flake-parts processes them as flake-parts modules first).
# Direct imports need pure NixOS options at the top level.
#
# ## Per-host wiring
#
# Each host that wants heartbeats imports this module directly:
#
#   ./../../modules/maintenance/heartbeat.nix
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
      # /run/secrets/heartbeat-endpoint.
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
      # Hardcoded to 5min — hosts that need different cadences can
      # override with `systemd.timers.heartbeat.timerConfig.OnUnitActiveSec`
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