# Observability role — umbrella option declarations.
#
# Modules contributing to `nixos.modules.observability` provide config
# only (no options, no assertions) so they don't conflict when
# flake-parts merges them. All NixOS option declarations for this
# role live here.
#
# This mirrors the disko convention: `modules/disko/disko.nix`
# declares `options.disko.device` while `modules/disko/btrfs-dedup.nix`
# contributes config only. flake-parts merges all files under
# `nixos.modules.observability` into a single deferred module, which
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
# Currently one contributor:
#   - modules/observability/node-exporter.nix — Prometheus node_exporter
#
# Adding a new observability feature:
#   1. Add the NixOS option declaration here.
#   2. Add the config in a new file under modules/observability/,
#      written as `{ pkgs, lib, ... }: { ... }` (no `config` arg).
{ lib, ... }:
{
  options.observability.nodeExporter = {
    enable = lib.mkEnableOption "Prometheus node_exporter on this host";

    # Bind address — typically a Netbird mesh IP of THIS host.
    # Leaving empty binds to 0.0.0.0 (NOT recommended; exposes
    # metrics to whatever can reach the port). The fleet uses
    # Netbird with wt0 + 100.77.0.0/16 (see pkgs/.update-config.json
    # #fleet.hosts for per-host IPs).
    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "100.77.119.175";
      description = "IP address to bind node_exporter on. Default: empty (= 0.0.0.0). Recommended: a Netbird mesh IP.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9100;
      description = "TCP port for node_exporter's metrics endpoint";
    };

    # Extra collectors to enable beyond the module defaults. Common
    # additions:
    #   systemd      : systemd unit state metrics (active/failed counts)
    #   processes    : per-process CPU/mem
    #   logind       : seat/session state
    #   systemd-timer: pending/running timer count (great for catching
    #                  missed btrfs-scrub / heartbeat timers)
    extraCollectors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "systemd" ];
      description = "Additional collectors to enable (--collector.<name>)";
    };
  };
}