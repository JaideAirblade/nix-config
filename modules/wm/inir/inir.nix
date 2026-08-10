# iNiR — Niri-native desktop shell role module.
#
# Parallel to modules/wm/dms/dms.nix and the previously-existing
# modules/wm/noctalia/noctalia.nix. Hosts opt in by adding
# `config.nixos.modules.inir` to their default.nix imports list.
#
# iNiR is a Wayland-Native desktop shell built on Quickshell: bar, launcher,
# dock, lock screen, notifications, control center, wallpaper picker, OSD
# overlays, clipboard history, and a Material-You-themed settings UI. It is
# purpose-built for Niri (full IPC integration via $NIRI_SOCKET) and has
# secondary Hyprland support via UWSM. Unlike Noctalia, iNiR ships no
# greeting flow — it is a session shell, not a login manager.
#
# ── Compositor compatibility (verified 2026-08-10) ─────────────────────────
# iNiR is Niri-primary. The NixOS module binds the inir.service to
# niri.service via `service.compositor = "niri"` (see `programs.inir.service`
# in the upstream flake). Hyprland works via `service.compositor = "hyprland"`
# and UWSM. UwU pairs it with Niri.
#
# ── Flake input (declared in flake.nix) ────────────────────────────────────
#   inir = github:snowarch/iNiR
#
# The flake exposes nixosModules.inir (and a sibling homeModules.inir).
# The NixOS module:
#   - declares programs.inir.{enable, package, extraPackages,
#     service.{enable, compositor}}
#   - creates a systemd user service `inir.service` that wants
#     `niri.service` and is partOf `graphical-session.target`
#   - sets INIR_SYSTEM_RUNTIME_DIR + QT_SCALE_FACTOR + QT_LOGGING_RULES
#     in the user service environment
#   - wraps the launcher with the full runtime dep set (quickshell,
#     wl-clipboard, cliphist, grim, slurp, pipewire, etc.)
#
# ── Niri config / keybinds ─────────────────────────────────────────────────
# iNiR's docs (docs/NIXOS.md) recommend declaring keybinds via
# `programs.niri.settings.binds` — but that option is exposed by the
# niri-flake (github:sodiboo/niri-flake), NOT by nixpkgs's built-in
# `programs.niri` module. We use the nixpkgs module here because the
# niri-flake is currently broken on this nixpkgs rev (see flake.nix
# comment block for the libdisplay-info_0_2 assertion failure).
# Therefore iNiR keybinds are NOT declared declaratively. Instead, the
# first-run `inir setup` on the user's account clones the bundled niri
# config from dots/.config/niri/config.kdl into ~/.config/niri/config.kdl
# The user can then edit that file freely; iNiR's niri-config.py
# performs surgical edits preserving comments on subsequent updates.
#
# ── Polkit ─────────────────────────────────────────────────────────────────
# NOTE: We do NOT enable polkit here. The niri NixOS module (imported by the
# host's per-host file) already sets `security.polkit.enable = true` and
# ships its own polkit-kde-agent via a systemd user service. Adding another
# agent here would conflict. Same caveat that the previous Noctalia module
# carried.
#
# ── gsettings schemas ──────────────────────────────────────────────────────
# Same XDG_DATA_DIRS prepending pattern as the DMS module — for any child
# app that runs `gsettings get/set` under the graphical session (Network
# Configurator, bluez-gnome, etc.).
#
# ── Reversibility ──────────────────────────────────────────────────────────
# Removing this file (or un-importing config.nixos.modules.inir from a host)
# and running `nixos-rebuild switch` fully removes the shell. The flake
# input stays defined in flake.nix — zero cost when unused.
{ inputs, ... }:
{
  nixos.modules.inir =
    { lib, pkgs, config, ... }:

    {
      imports = [
        inputs.inir.nixosModules.inir
      ];

      # gsettings schema paths — same pattern as DMS/Noctalia shell modules.
      environment.sessionVariables.XDG_DATA_DIRS = lib.mkBefore [
        "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
        "${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}"
      ];

      # iNiR shell — NixOS module from upstream. The module is opt-in
      # (enable = false by default), so we explicitly turn it on here.
      programs.inir = {
        enable = true;
        # The `service.compositor = "niri"` default wires the user unit
        # under `niri.service.wants/inir.service`. The unit is also partOf
        # `graphical-session.target`, so it starts under any session that
        # pulls niri in.
        service.compositor = "niri";
        # Put the niri client binary on iNiR's PATH so features that call
        # `niri msg` (workspace switching, IPC) use the same package
        # version as the compositor.
        extraPackages = [ config.programs.niri.package ];
      };
    };
}
