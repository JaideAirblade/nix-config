# Maintenance role — umbrella option declarations.
#
# Modules contributing to `nixos.modules.maintenance` provide config
# only (no options, no assertions) so they don't conflict when
# flake-parts merges them. All NixOS option declarations for this
# role live here.
#
# This mirrors the disko convention: `modules/disko/disko.nix`
# declares `options.disko.device` while `modules/disko/btrfs-dedup.nix`
# contributes config only. flake-parts merges all files under
# `nixos.modules.maintenance` into a single deferred module, which
# the NixOS module system then processes on each host that imports
# the role.
#
# This file takes `{ lib, ... }:` (no `config`/`pkgs`/etc.) because
# flake-parts eagerly evaluates deferred modules when computing
# `processedFlake` and other flake outputs — at that point only
# `lib` and `inputs` are in scope. Reading `config.<option>` here
# would fail at flake-time. The NixOS module system wires everything
# together at host eval time, so the options are still resolvable
# from inside the unit definitions declared by sibling files.
#
# Currently two contributors:
#   - modules/maintenance/smartd.nix       — fleet-wide smartd config
#   - modules/maintenance/heartbeat.nix    — Uptime Kuma dead-man's switch
#
# Adding a new maintenance feature:
#   1. Add the NixOS option declaration here.
#   2. Add the config in a new file under modules/maintenance/, written
#      as `{ lib, ... }: { ... }` or `{ pkgs, lib, ... }: { ... }` (no
#      `config` arg — see comment above).
{ lib, ... }:
{
  options.maintenance.heartbeat = {
    enable = lib.mkEnableOption "Send dead-man's-switch heartbeat pings to Uptime Kuma";

    # Sops key holding the Uptime Kuma push URL. The file is rendered
    # to `/run/secrets/<key-with-underscores-replaced-by-hyphens>` —
    # e.g. `heartbeat_endpoint` renders to `/run/secrets/heartbeat-endpoint`.
    # The host's `users.nix` or service-specific module must declare
    #   sops.secrets.heartbeat_endpoint = { ... };
    # for this to work.
    sopsKey = lib.mkOption {
      type = lib.types.str;
      default = "heartbeat_endpoint";
      description = "Key inside the sops file holding the Uptime Kuma push URL";
    };

    # How often to ping. 300s = 5 minutes (matches Uptime Kuma default
    # retry interval). Hosts that miss >3 consecutive pings are flagged
    # DOWN.
    intervalSeconds = lib.mkOption {
      type = lib.types.ints.between 30 86400;
      default = 300;
      description = "Heartbeat ping interval in seconds";
    };
  };
}