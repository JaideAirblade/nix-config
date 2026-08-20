# Private management mesh: Netbird (WireGuard) supplies the encrypted
# network plane, while ordinary OpenSSH retains the existing pinned
# host/user key trust path.
#
# This module is the SOLE mesh role on every managed host as of 2026-08-11.
# The previous Tailscale role (modules/network/tailscale-mesh.nix) was
# removed in the same cleanup commit; hosts that previously selected both
# `nixos.modules.remoteMesh` and `nixos.modules.netbirdMesh` now select
# only `nixos.modules.netbirdMesh`. See docs/netbird-mesh.md for the
# migration rationale.
#
# The outer layer (this file) is a flake-parts module that returns
# `nixos.modules.netbirdMesh` — a deferredModule attrset. The NixOS
# sub-module is the inner function inside that attrset.
{ lib, inputs, ... }:
{
  nixos.modules.netbirdMesh =
    { config, lib, pkgs, ... }:
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

      # Per-instance wrapper read + shim derivation. Both are wrapped
      # in `lib.optionalAttrs cfg.dms.enable` so neither evaluation
      # happens when the flag is off. Reading
      # `config.services.netbird.clients.mesh.wrapper` eagerly fails
      # for hosts that don't opt into netbirdMesh (the wrapper
      # attribute is only defined when the upstream NixOS module has
      # declared the instance). Forcing the evaluation for hosts
      # without `dms.enable` (the default) would fail with "attribute
      # 'wrapper' missing".
      dmsShim = lib.optionalAttrs cfg.dms.enable {
        # Read the per-instance wrapper that the NixOS netbird module
        # builds for the `mesh` client. This is the SAME derivation
        # that `netbird-mesh.service` ExecStarts and that the module
        # already adds to `environment.systemPackages`. Reading it
        # from `config` rather than hardcoding `/nix/store/…` keeps
        # the shim in sync with any future netbird package version
        # bump.
        wrapper = config.services.netbird.clients.mesh.wrapper;

        # Tiny passthrough package: a makeWrapper of the existing
        # wrapper, renamed `netbird-mesh` → `netbird`. All `NB_*` env
        # vars the wrapper exports propagate through unchanged.
        package = pkgs.stdenv.mkDerivation {
          pname = "netbird-mesh-shim";
          version = pkgs.netbird.version;

          nativeBuildInputs = [ pkgs.makeWrapper ];

          buildCommand = ''
            mkdir -p "$out/bin"
            cp -r ${dmsShim.wrapper}/bin/* "$out/bin/"
            mv "$out/bin/netbird-mesh" "$out/bin/netbird"
            wrapProgram "$out/bin/netbird" \
              --prefix PATH : "${lib.getBin dmsShim.wrapper}/bin"
          '';

          meta = {
            description = "User-facing `netbird` shim that delegates to the NixOS-supervised netbird-mesh wrapper. For use by the DMS NetbirdStatus plugin, netbird-ui, and any other tooling that hardcodes `which netbird`.";
            mainProgram = "netbird";
            platforms = [ "x86_64-linux" ];
          };
        };
      };
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

        # ─────────────────────────────────────────────────────────────────
        # Daemon socket access — additional users beyond the canonical jaide
        # ─────────────────────────────────────────────────────────────────
        # The hardened Netbird daemon runs as user `netbird-mesh` and group
        # `netbird-mesh`, and its per-instance runtime directory is mode
        # 0750 (per the upstream NixOS module's `RuntimeDirectoryMode`).
        # That means only the `netbird-mesh` group can traverse
        # `/var/run/netbird-mesh/` to reach the unix socket. The upstream
        # module's own docs (services/networking/netbird.nix ~line 272)
        # document this as a deliberate hardening choice and tell the
        # operator to add users to the daemon group:
        #
        #   users.users.<user>.extraGroups = [ "netbird-mesh" ];
        #
        # This role module always adds `jaide` to the `netbird-mesh`
        # group when the mesh is enabled (see the `users.users`
        # attrset in the config block below) so the canonical human
        # account can talk to the daemon for the netbird-ui GUI, the
        # `netbird status` CLI, and the DMS NetbirdStatus plugin.
        # Hosts that have a `mkForce` on `users.users.jaide.extraGroups`
        # (e.g. TSBW-W01800's "work" override wipes the personal list)
        # need to opt back in via this option — list the user there
        # and the role will merge the group into their forced extras.
        #
        # Each listed user must already exist via the standard NixOS
        # `users.users.<name>` declaration; the role adds the
        # `netbird-mesh` group to their `extraGroups`. The role does
        # NOT create the user — that's the host's job (lives in
        # hosts/<host>/users/). Listings that don't match a real user
        # are silently ignored (gated on `config.users.users ? <name>`)
        # so a host that doesn't declare them yet stays buildable.
        daemonSocketUsers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "jaide" ];
          description = "Additional local users (beyond the canonical `jaide` account) that should be allowed to talk to the netbird-mesh daemon over its unix socket. Each name is added to the `netbird-mesh` group via `users.users.<name>.extraGroups`.";
        };

        # ------------------------------------------------------------------
        # Mesh DNS resolver bind address — per-host, opt-in
        # ------------------------------------------------------------------
        # When set, the netbird daemon serves `*.netbird.cloud` queries
        # on this address+port instead of the default (the daemon's own
        # mesh IP at an implementation-chosen port, currently 5053).
        # The only host that opts in today is Luna-Server: its daemon
        # binds on 127.0.0.1:5353 so AdGuard can forward `*.netbird.cloud`
        # via a single `[/netbird.cloud/]127.0.0.1:5353` upstream entry
        # (port 53 is taken by AdGuard; 5353 is the standard mDNS port
        # and avoids the CAP_NET_BIND_SERVICE cap the daemon would
        # otherwise need for ports < 1024). UwU and TSBW leave this
        # null — their daemons bind on the default mesh IP:5053 and
        # their system resolvers route `*.netbird.cloud` to Luna-Server's
        # AdGuard over the mesh, which then forwards to the loopback
        # daemon.
        #
        # Single address: the daemon only supports one. Picking the
        # right address matters because:
        # - `127.0.0.1` only works from the local host (AdGuard → daemon
        #   on the same host).
        # - the mesh IP works from any peer that can route to it, but
        #   requires opening UDP/TCP firewall ports on `wt0`.
        dnsResolverAddress = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "127.0.0.1";
          description = "Address that the netbird-mesh daemon should serve `*.netbird.cloud` DNS on. null means the daemon's default (its own mesh IP at port 5053). See module header for the Luna-Server / UwU / TSBW-W01800 split.";
        };

        dnsResolverPort = lib.mkOption {
          type = lib.types.ints.between 1 65535;
          default = 5353;
          description = "Port the daemon should serve mesh DNS on (paired with `dnsResolverAddress`).";
        };

        # ------------------------------------------------------------------
        # DMS-visible `netbird` CLI shim
        # ------------------------------------------------------------------
        # The NixOS netbird module exposes each instance as
        # `netbird-mesh` (derived from `services.netbird.clients.<name>`
        # where the instance attr is `mesh` and `bin.suffix = "mesh"`).
        # The raw binary is intentionally NOT on $PATH — only the
        # systemd wrapper is. That breaks any consumer that hardcodes
        # `command -v netbird`:
        #   - DMS NetbirdStatus plugin (github.com/Dadangdut33/
        #     dms-plugins/NetbirdStatus) probes `which netbird` and
        #     shows "NetBird not installed" if the probe fails.
        #   - netbird-ui (the upstream GUI) launches `netbird status`
        #     via subprocess.
        #   - ad-hoc shell scripts that assume the upstream package
        #     name.
        #
        # Setting `dms.enable = true` builds a tiny derivation that
        # wraps the per-instance wrapper under the name `netbird` and
        # adds it to `environment.systemPackages`. The wrapper bakes
        # in every `NB_*` env var the upstream NixOS module requires
        # (NB_DAEMON_ADDR, NB_CONFIG, NB_STATE_DIR, NB_INTERFACE_NAME,
        # NB_WIREGUARD_PORT, NB_LOG_LEVEL, NB_SERVICE, NB_LOG_FILE),
        # so the shim inherits them via makeWrapper's passthrough —
        # no env-var re-derivation is needed.
        #
        # Hosts that DON'T need this (LaptopAP — no DMS; Projet-
        # Printserver — printserver role, no DMS) leave it at the
        # default `false`. Hosts that run DMS (UwU, Luna-Server,
        # TSBW-W01800) opt in.
        dms = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Whether to expose a user-facing `netbird` CLI on $PATH
              for desktop-environment consumers (DankMaterialShell
              NetbirdStatus plugin, netbird-ui, shell scripts that
              hardcode `which netbird`). The shim delegates to the
              supervised `netbird-mesh` wrapper and inherits its
              env vars; the daemon itself is untouched.
            '';
          };
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

          # Mesh DNS resolver bind. `dns-resolver.address` is null by
          # default in the upstream module, which makes the daemon
          # serve `*.netbird.cloud` on its own mesh IP at port 5053.
          # Hosts that want a stable, predictable resolver bind (so
          # the local resolver chain can forward to a known socket)
          # set `dnsResolverAddress` via `services.netbirdMesh`.
          # See the option doc on `dnsResolverAddress` for the
          # Luna-Server / UwU / TSBW-W01800 split.
          dns-resolver = lib.mkIf (cfg.dnsResolverAddress != null) {
            address = cfg.dnsResolverAddress;
            port = cfg.dnsResolverPort;
          };
        };

        # ------------------------------------------------------------------
        # Routing features (client mode)
        # ------------------------------------------------------------------
        # Enables IP forwarding and the routing-peer features — required
        # for any peer that may route traffic on behalf of others (e.g.
        # Luna-Server routing UwU's direct-link traffic to the internet).
        # Restricted to "client" mode: nodes are not exit nodes for the
        # whole mesh.
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
        # Same port list as the previous Tailscale role, bound to the
        # Netbird interface name (`wt0`). Port 22 = OpenSSH; 8080 =
        # Hermes WebUI; 8642/9119/9131 = Hermes Mobile Bridge
        # (gateway/dashboard/bridge). 3000 = AdGuard Home web UI on mesh
        # only. 443 = Gitea + dashboard ingress. Permissions in the
        # Netbird policy mirror the previous Tailscale ACL (now stored in
        # modules/network/netbird-policy.json).
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
        users.users = {
          # Daemon socket access — merge each user declared in
          # cfg.daemonSocketUsers into the `netbird-mesh` group so they
          # can reach the unix socket at `/var/run/netbird-mesh/sock`.
          # The upstream NixOS module declares the `netbird-mesh` group
          # itself when hardened mode is on, so we don't re-declare it.
          # We gate each entry on the user's *existence* so naming a
          # non-existent user on a host fails the build loudly instead
          # of silently creating a phantom account.
          jaide = {
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKozofCo3TsmA85edEMGsysfAkLf1/wWL3cv+DR0Ck04 jaide_nixos"
            ];
            extraGroups = lib.mkAfter [ "netbird-mesh" ];
          };
        } // lib.foldl' (acc: name:
          acc // lib.optionalAttrs (config.users.users ? ${name}) {
            ${name}.extraGroups = lib.mkAfter [ "netbird-mesh" ];
          }) { } cfg.daemonSocketUsers;

        # ------------------------------------------------------------------
        # Public role metadata (echo of the pre-Netbird required-tag file)
        # ------------------------------------------------------------------
        # Netbird assigns groups at enrollment time, not via a
        # filesystem marker. We keep an analogous
        # `/etc/netbird/required-group` file so pre-enrollment sanity
        # checks report the intended role without touching the
        # coordination server.
        environment.etc."netbird/required-group".text = "${cfg.nodeRole}\n";

        # ------------------------------------------------------------------
        # DMS-visible `netbird` CLI shim (opt-in)
        # ------------------------------------------------------------------
        # See the `services.netbirdMesh.dms.enable` option above for
        # the full rationale. When enabled, the shim package (built
        # above in `dmsShim.package`, lazily so it doesn't try to
        # read the wrapper for hosts that don't opt in) is added to
        # the system profile so `command -v netbird` succeeds for any
        # user that pulls this profile into their shell.
        environment.systemPackages = lib.mkIf cfg.dms.enable [ dmsShim.package ];
      };
    };
}
