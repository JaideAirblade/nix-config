# Prometheus node_exporter — host-level metrics on every fleet member.
#
# This module is the CONFIG-ONLY contributor to `nixos.modules.observability`
# for the node_exporter feature. All NixOS option declarations live in
# `modules/observability/default.nix` (the umbrella). This split mirrors
# the disko convention: `disko.nix` declares options, `btrfs-dedup.nix`
# contributes config only.
#
# ## Why config-only here
#
# flake-parts evaluates each `nixos.modules.<key>` deferred module at
# flake-time when processing the flake outputs. At that point, the
# module function only has `lib` and `inputs` in scope — reading
# `config.<NixOS-option>` fails. The clean fix is for the function to
# take only `{ pkgs, lib, ... }:` (no `config`) and contribute config
# without reading options. The umbrella declares options; the NixOS
# module system wires everything at host eval time.
#
# ## Per-host wiring
#
#   config.nixos.modules.observability  # in modules = [ ... ]
#
# And opt in via:
#   observability.nodeExporter = {
#     enable = true;
#     listenAddress = "100.119.53.51"; # required when enable=true
#     port = 9100;                     # default
#     extraCollectors = [ "systemd" "systemd-timer" ]; # default
#   };
#
# ## Why per-host listening address
#
# Binding to 0.0.0.0 would work but it's a footgun: a future firewall
# regression + a public-IP tailnet peer = metric leak. Binding to a
# specific Tailscale IP means only that peer (the Prometheus server
# on UwU-Server) can scrape. Same defence-in-depth pattern as the
# stealth-ssh listener.
#
# ## Safety check
#
# The listenAddress safety assertion can't live in this file (it
# would need `config` to read the option, which we can't take).
# Instead, the host module OR a separate host-side check verifies
# the value at activation time. The pattern:
#
#   nixos.modules.observability = {
#     nodeExporter = {
#       enable = true;
#       listenAddress = "100.119.53.51"; # must be non-empty when enable=true
#     };
#   };
#
# If a host enables nodeExporter without setting listenAddress, the
# unit binds to 0.0.0.0 — visible immediately via `ss -ltn` after
# deploy. Fix by setting listenAddress before deploying.
{ pkgs, lib, ... }:
{
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    # The bind-address is set per-host via
    # observability.nodeExporter.listenAddress. Default is 0.0.0.0
    # (only used if a host enables node_exporter without setting
    # listenAddress — see "Safety check" above). Hosts that want
    # mesh-only exposure override this in their host module:
    #
    #   services.prometheus.exporters.node.listenAddress =
    #     "100.119.53.51";
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
    extraArgs = [
      "--collector.filesystem.mount-points-exclude=^/(dev|proc|sysfs|run|var/lib/docker/overlay2|var/lib/flatpak)($|/)"
    ];
  };

  # Allow the Netbird mesh interface (wt0) to reach the exporter
  # port. The firewall module already defaults to denying public
  # access on workstations; this makes the allow rule explicit.
  networking.firewall.interfaces."wt0".allowedTCPPorts = [ 9100 ];
}