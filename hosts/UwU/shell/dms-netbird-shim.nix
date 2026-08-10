# User-facing `netbird` shim for the DankMaterialShell (DMS) NetbirdStatus
# plugin on UwU.
#
# ── Why this file exists ──────────────────────────────────────────────────────
# The DMS "NetbirdStatus" plugin (github.com/Dadangdut33/dms-plugins/NetbirdStatus)
# probes for a `netbird` binary on $PATH by running `which netbird` and
# setting `netbirdInstalled = (exitCode === 0)`. On UwU the Netbird mesh is
# managed by the NixOS module `nixos.modules.netbirdMesh`, which intentionally
# does NOT expose the raw `netbird` binary on $PATH — only the per-instance
# systemd wrapper `netbird-mesh` is exposed (its name is derived from the
# instance attr `services.netbird.clients.mesh`, where `mkBin "netbird"`
# yields `netbird-mesh` because the instance's `bin.suffix` is `mesh`).
#
# The plugin therefore prints "NetBird not installed" even though
# `netbird-mesh.service` is active and the mesh is up. The plugin's own
# README confirms this is its only probe:
#
#   ### "Not installed" message
#   If you see "NetBird not installed", make sure NetBird is installed and
#   the `netbird` binary is accessible in your PATH.
#
# ── What this file does ──────────────────────────────────────────────────────
# Builds a tiny derivation that wraps the existing `netbird-mesh` wrapper
# under the name `netbird`. The systemd wrapper already bakes in every
# required `NB_*` env var (NB_DAEMON_ADDR, NB_CONFIG, NB_STATE_DIR,
# NB_INTERFACE_NAME, NB_WIREGUARD_PORT, NB_LOG_LEVEL, NB_SERVICE,
# NB_LOG_FILE), so we just wrap it again with makeWrapper and rename the
# binary. Because we wrap the *wrapper*, the env vars carry over through
# the bash script's `export` lines — no env-var re-derivation is needed.
#
# The resulting `/run/current-system/sw/bin/netbird` is a passthrough
# that:
#   - resolves `which netbird` to exit 0 (fixes the plugin's install probe)
#   - routes `netbird status / up / down / service <…>` to the supervised
#     mesh instance (NB_SERVICE=netbird-mesh, NB_DAEMON_ADDR=unix:///var/run/netbird-mesh/sock)
#   - does not affect the daemon: it is still supervised by systemd as
#     `netbird-mesh.service`; this shim is a CLI-only entry point.
#
# ── Scope ────────────────────────────────────────────────────────────────────
# Host-scoped to UwU via the standard `nixos.hosts."UwU"` flake-parts
# shape that every other file in hosts/UwU/ uses. Auto-discovered by
# `collectModules ./hosts "hosts"` in flake.nix. NOT added to the role
# module `modules/network/netbird-mesh.nix` — other hosts that opt into
# `nixos.modules.netbirdMesh` may not run DMS, so a DMS-specific shim
# belongs at the host level, not the role level.
#
# ── Reversibility ────────────────────────────────────────────────────────────
# Removing this file (or setting `dms.enable = false` below) and running
# `nixos-rebuild switch` fully removes the `netbird` shim from $PATH.
# The supervised `netbird-mesh` wrapper and the daemon are untouched —
# they live in `modules/network/netbird-mesh.nix` and the upstream
# NixOS netbird module respectively.
#
# ── References ──────────────────────────────────────────────────────────────
#   Plugin repo:           github.com/Dadangdut33/dms-plugins/NetbirdStatus
#   Plugin probe code:     NetbirdWidget.qml (the `whichProcess` block —
#                          sets `netbirdInstalled = (exitCode === 0)`)
#   Wrapper derivation:    upstream NixOS netbird module
#                          nixos/modules/services/networking/netbird.nix
#                          lines 310–342 (the `client.wrapper` option)
#   Per-instance env vars: same file, lines 196–209
_:
{
  nixos.hosts."UwU" =
    { config, lib, pkgs, ... }:

    let
      # Read the per-instance wrapper that the NixOS netbird module builds
      # for the `mesh` client. This is the SAME derivation that the systemd
      # unit `netbird-mesh.service` ExecStarts and that the module already
      # adds to `environment.systemPackages` (see netbird.nix line 508).
      # Reading it from `config` rather than hardcoding `/nix/store/…` keeps
      # this shim in sync with any future netbird package version bump.
      meshWrapper = config.services.netbird.clients.mesh.wrapper;

      # Tiny passthrough package: a makeWrapper of the existing wrapper,
      # renamed to `netbird`. All `NB_*` env vars the wrapper exports
      # propagate through unchanged.
      netbirdShim = pkgs.stdenv.mkDerivation {
        pname = "netbird-mesh-shim";
        # The wrapper derivation exposes only `name`, not `version` — derive
        # the version from the netbird package itself so the shim stays in
        # sync with whatever netbird version the NixOS module builds against.
        version = pkgs.netbird.version;

        nativeBuildInputs = [ pkgs.makeWrapper ];

        # We do not need any build inputs — we just symlink the wrapper's
        # /bin into a fresh tree and rename `netbird-mesh` → `netbird`.
        # Using a derivation (rather than `environment.systemPackages`
        # symlinks) keeps the rename atomic and tracked in the Nix store.
        buildCommand = ''
          mkdir -p "$out/bin"
          # Bring every binary from the upstream wrapper into our shim.
          cp -r ${meshWrapper}/bin/* "$out/bin/"
          # Rename `netbird-mesh` → `netbird` so `which netbird` succeeds.
          mv "$out/bin/netbird-mesh" "$out/bin/netbird"
          # makeWrapper on the renamed binary to ensure RPATH / library
          # references track the upstream wrapper's closure. makeWrapper
          # is idempotent here — it adds a small wrapper script but
          # preserves every `NB_*` env var the original wrapper set.
          wrapProgram "$out/bin/netbird" --prefix PATH : "${lib.getBin meshWrapper}/bin"
        '';

        meta = {
          description = "User-facing `netbird` shim that delegates to the NixOS-supervised netbird-mesh wrapper. For use by the DMS NetbirdStatus plugin and any other tooling that hardcodes `which netbird`.";
          mainProgram = "netbird";
          platforms = [ "x86_64-linux" ];
        };
      };

      cfg = config.services.netbirdMesh;
    in
    {
      options.services.netbirdMesh.dms = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether to expose the user-facing `netbird` shim on $PATH for
            desktop-environment consumers (DankMaterialShell NetbirdStatus
            plugin, scripts that hardcode `which netbird`, etc.).
            Does not affect the supervised daemon; it is only a CLI shim.
          '';
        };
      };

      config = lib.mkIf (cfg.enable && cfg.dms.enable) {
        # Add the shim to the system profile. Because DMS runs as the
        # logged-in user (via the `luna` account in this case) under the
        # graphical session, the shim is reachable both from interactive
        # shells and from the DMS plugin's execDetached calls.
        environment.systemPackages = [ netbirdShim ];

        # Convenience shell alias so a logged-in user can still call the
        # supervised instance by its real name.
        programs.bash.shellAliases.netbird-mesh-status = "netbird-mesh status";
      };
    };
}