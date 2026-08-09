# Private management mesh: Netbird (WireGuard) supplies the encrypted
# network plane, while ordinary OpenSSH retains the existing pinned
# host/user key trust path.
#
# This module is the Netbird parallel to modules/network/tailscale-mesh.nix.
# During the cutover (2026-08-09) hosts select BOTH nixos.modules.remoteMesh
# (Tailscale — keeps the live mesh up) and nixos.modules.netbirdMesh (this
# module — registers the new Netbird mesh). Once every reachable peer has
# been verified on Netbird and the Tailscale module is removed, hosts
# select only nixos.modules.netbirdMesh.
#
# The outer layer (this file) is a flake-parts module that returns
# `nixos.modules.netbirdMesh` — a deferredModule attrset — in the same
# shape as tailscale-mesh.nix returns `nixos.modules.remoteMesh`. The
# NixOS sub-module is the inner function inside that attrset.
{ lib, inputs, ... }:
{
  nixos.modules.netbirdMesh =
    { config, lib, ... }:
    let
      cfg = config.services.netbirdMesh;
      # Stable interface name across all hosts. Matches the Netbird
      # NixOS module default but written explicitly so firewall rules
      # below can attach to a known string.
      wtInterface = "wt0";
      # SOPS-nix renders files at /run/secrets/<key> by default. The
      # key in nixos-secrets/secrets/shared/netbird-setup-key.yaml is
      # named `netbird_setup_key` — sops-nix normalises underscores to
      # hyphens in the rendered filename, so the runtime path is:
      #   /run/secrets/netbird-setup-key
      # The previous Tailscale-era comment about "NOTE: if your setup
      # key is reusable, make sure it is not copied to the Nix store"
      # is resolved by SOPS decryption at activation time — the file
      # is rendered into a tmpfs at /run/secrets, never into the
      # read-only Nix store.
      setupKeyPath = "/run/secrets/netbird-setup-key";
    in
    {
      # Parallel option namespace to `services.privateMesh` (Tailscale).
      # Hosts read this during the cutover alongside `services.privateMesh`.
      # Both modules co-exist; the Tailscale module keeps the live mesh
      # up while the Netbird mesh registers the new peers.
      options.services.netbirdMesh = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the Netbird mesh role on this host.";
        };

        nodeRole = lib.mkOption {
          type = lib.types.enum [ "private" "work" "printserver" "personal" ];
          description = "Access-control role assigned to this Netbird mesh node. Mapped 1:1 to a Netbird group of the same name (no `tag:` prefix in Netbird).";
        };

        exposeSshOnLan = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Also expose OpenSSH through the host's ordinary firewall. Mirrors the Tailscale-era option; usually the LAN SSH path is closed on private/work/personal nodes and only open on the bastion server.";
        };
      };

      config = lib.mkIf cfg.enable {
        # ------------------------------------------------------------------
        # SOPS secret: Netbird setup key
        # ------------------------------------------------------------------
        # The setup key is stored in nixos-secrets (flake input
        # `nixos-secrets`). The file is rendered at
        # /run/secrets/netbird-setup-key by sops-nix at activation
        # time. The netbird-mesh systemd unit runs as user
        # netbird-mesh / group netbird-mesh, so the file is owned by
        # that user/group with mode 0440 (read-only, owner+group).
        # Without this declaration, sops-nix doesn't render the file
        # and the netbird-mesh-login.service fails with
        # status=243/CREDENTIALS.
        sops.secrets.netbird-setup-key = {
          sopsFile = "${inputs.nixos-secrets}/secrets/shared/netbird-setup-key.yaml";
          owner = "netbird-mesh";
          group = "netbird-mesh";
          mode = "0440";
        };

        # ------------------------------------------------------------------
        # Netbird client (single instance, named `mesh`)
        # ------------------------------------------------------------------
        # The instance name `mesh` derives the systemd unit name
        # `netbird-mesh.service` and the binary `netbird-mesh` on PATH.
        # The interface name is fixed to `wt0` so the firewall /
        # direct-link DNS rules below can reference the same string
        # everywhere.
        services.netbird.clients.mesh = {
          # Schema note (NixOS module): the `clients.<name>` attrset
          # has no `enable` field — presence of the entry IS the
          # enable. The `services.netbirdMesh.enable` boolean in our
          # outer role is what gates whether this whole block is
          # present at all (via lib.mkIf cfg.enable above).

          # Required: port the Wireguard UDP listener listens on for
          # direct peer-to-peer paths. The Netbird management server
          # (netbird.io) handles coordination; the deny-by-default
          # Netbird policy on the management console enforces which
          # peers may initiate connections.
          port = 51821;

          # Stable interface name across all hosts.
          interface = wtInterface;

          # Default true — explicit for documentation.
          openFirewall = true;
          openInternalFirewall = true;

          # Automated login with the SOPS-encrypted setup key. The
          # path `/run/secrets/netbird-setup-key` is rendered by
          # sops-nix at activation time and is only readable by the
          # netbird-mesh systemd unit. Nothing about the key is
          # exposed to /nix/store.
          login = {
            enable = true;
            setupKeyFile = setupKeyPath;
          };
        };

        # ------------------------------------------------------------------
        # Routing features (mirrors services.tailscale.useRoutingFeatures)
        # ------------------------------------------------------------------
        # Enables IP forwarding and the routing-peer features — required
        # for any peer that may route traffic on behalf of others (e.g.
        # UwU-Server routing UwU's direct-link traffic to the internet).
        # Restricted to "client" mode in line with the Tailscale policy:
        # nodes are not exit nodes for the whole mesh.
        services.netbird.useRoutingFeatures = "client";

        # ------------------------------------------------------------------
        # DNS integration: NOT enabled via systemd-resolved
        # ------------------------------------------------------------------
        # Netbird's NixOS module supports two DNS integration paths:
        # either `services.resolved.enable = true` (with systemd-resolved
        # as the system resolver) or leave it disabled and use openresolv
        # (the module's default when resolved is off). We do NOT enable
        # resolved here — hosts with a custom direct-link DNS pin
        # (e.g. UwU pointing system DNS at AdGuard Home via a custom
        # environment.etc."resolv.conf".text) would conflict with
        # resolved's stub-resolv.conf assignment on the same option.
        # When the AdGuard → Netbird split-horizon forward is wired
        # (deferred to Phase 3), the upstream DNS resolver IP for
        # Netbird's managed domain is set via `dns-resolver.address`
        # per-client. See docs/netbird-mesh.md for the configuration
        # pattern.

        # ------------------------------------------------------------------
        # OpenSSH — identical to the Tailscale mesh configuration.
        # ------------------------------------------------------------------
        # Pinning the trust path to OpenSSH + pinned host keys + the
        # jaide_nixos pubkey is the whole point of the "transport-only"
        # design. Netbird is the encrypted wire, the same way Tailscale
        # was. We never enable Netbird's experimental SSH-broker.
        services.openssh = {
          enable = true;
          openFirewall = cfg.exposeSshOnLan;
          settings = {
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
            PermitRootLogin = lib.mkDefault "no";
          };
        };

        # ------------------------------------------------------------------
        # Firewall: Netbird interface allowlist
        # ------------------------------------------------------------------
        # Same port list as the Tailscale role, bound to the Netbird
        # interface name (`wt0`). See the corresponding comments in
        # modules/network/tailscale-mesh.nix for the rationale of each
        # port. Port 22 = OpenSSH; 8080 = Hermes WebUI; 8642/9119/9131
        # = Hermes Mobile Bridge (gateway/dashboard/bridge). 3000 =
        # AdGuard Home web UI on tailnet only. 443 = Gitea + dashboard
        # ingress. Permissions in the Netbird policy mirror the
        # Tailscale ACL.
        networking.firewall.interfaces.${wtInterface}.allowedTCPPorts = [
          22
          443
          3000
          3001
          3002
          3030
          8080
          8642
          9119
          9131
          19999
          28981
        ];

        # ------------------------------------------------------------------
        # Jaide's pinned SSH public key — unchanged.
        # ------------------------------------------------------------------
        # The private half never enters this repo. The same key is also
        # authorised on every Tailscale-era host; for the Netbird era
        # it remains the sole human admin/recovery path.
        #
        # NOTE: when both remoteMesh (Tailscale) and netbirdMesh
        # (Netbird) are active on the same host during the cutover, the
        # Nix module system merges these two lists into a single
        # authorised-keys list. The key is identical so the merge is a
        # no-op.
        users.users.jaide.openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKozofCo3TsmA85edEMGsysfAkLf1/wWL3cv+DR0Ck04 jaide_nixos"
        ];

        # ------------------------------------------------------------------
        # Public role metadata (echo of the Tailscale required-tag file)
        # ------------------------------------------------------------------
        # Netbird assigns groups at enrollment time, not via a
        # filesystem marker. We keep an analogous
        # `/etc/netbird/required-group` file so pre-enrollment sanity
        # checks (the same pattern as the tailscale-required-tag file)
        # report the intended role without touching the coordination
        # server.
        environment.etc."netbird/required-group".text = "${cfg.nodeRole}\n";
      };
    };
}
