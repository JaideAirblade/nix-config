# Prometheus node_exporter — host-level metrics on every fleet member.
#
# Pure NixOS module (no `nixos.modules.observability = ...` wrapper).
# Hosts import it directly into their `modules = [ ... ]` list.
#
# ## Why pure NixOS module shape
#
# flake-parts evaluates all `imports = [ ... ]` as NixOS modules.
# When a module's top-level return value is
# `{ nixos.modules.observability = <function> }`, flake-parts errors
# with `error: The option 'nixos' does not exist`. The wrapper only
# works for files auto-imported by the dendritic walker; direct
# imports need pure NixOS options (`services.*`, `networking.*`) at
# the top level.
#
# ## Per-host wiring
#
# Hosts import this module directly:
#
#   ./../../modules/observability/node-exporter.nix
#
# ## Why per-host listening address
#
# Binding to 0.0.0.0 would work but it's a footgun: a future firewall
# regression + a public-IP tailnet peer = metric leak. Binding to a
# specific Tailscale IP means only that peer (the Prometheus server
# on UwU-Server) can scrape. Same defence-in-depth pattern as the
# stealth-ssh listener.
#
# The bind address is set per-host via `services.prometheus.exporters.node.listenAddress`
# in the host module. The default is 0.0.0.0 (only used if a host
# enables node_exporter without setting listenAddress — see
# observability/nodeExporter.listenAddress option declaration in
# modules/observability/options.nix).

{ pkgs, lib, ... }:

{
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    listenAddress = "0.0.0.0";
    enabledCollectors = [ "systemd" ];
    # Skip pseudo and virtual filesystems — they're noise that
    # floods /metrics with no actionable data.
    disabledCollectors = [
      "wifi"             # not relevant on most hosts
      "powersupplyclass" # noise; smartd + acpi handle this better
    ];
    # Filesystem filter — only report on real mountpoints.
    # Default regex from upstream is "(snap|var/lib/kubelet|pods)";
    # we extend to also skip overlay mounts from Docker/Flatpak.
    extraFlags = [
      "--collector.filesystem.mount-points-exclude=^/(dev|proc|sysfs|run|var/lib/docker/overlay2|var/lib/flatpak)($|/)"
    ];
  };

  # Allow the Netbird mesh interface (wt0) to reach the exporter
  # port. The firewall module already defaults to denying public
  # access on workstations; this makes the allow rule explicit.
  networking.firewall.interfaces."wt0".allowedTCPPorts = [ 9100 ];
}