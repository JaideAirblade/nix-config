# Noctalia Shell — desktop shell + greeter module.
#
# Parallel to modules/wm/dms/dms.nix. Hosts opt in by adding
# `config.nixos.modules.noctalia` to their default.nix imports list.
#
# Noctalia is a Wayland-native desktop shell: bars, launcher, dock, lock
# screen, notifications, control center, wallpaper picker, OSD overlays,
# tray, clipboard history, and a TOML configuration system with hot
# reload. It does NOT depend on Qt or GTK for its own UI; it integrates
# with the user's compositor via the Wayland layer-shell protocol and
# (where available) the ext-workspace-v1 protocol for workspace awareness.
#
# ── Compositor compatibility (verified 2026-08-10) ─────────────────────────
# Noctalia supports Niri, Hyprland, Sway, Scroll, Mango, Labwc, Triad, dwl,
# and other wlroots-ish Wayland compositors. UwU pairs it with niri.
# Stage 2 may pair it with Hyprland or Mango on other hosts.
#
# ── Flake inputs (declared in flake.nix) ───────────────────────────────────
#   noctalia         = github:noctalia-dev/noctalia
#   noctalia-greeter = github:noctalia-dev/noctalia-greeter
#
# Both expose `nixosModules.default` per their flake.nix files. The noctalia
# module imports `./nix/nixos-module.nix` which:
#   - declares programs.noctalia.{enable, package, systemd.{enable, target},
#     recommendedServices.enable}
#   - sets `disabledModules = [ "programs/wayland/noctalia.nix" ]` to override
#     nixpkgs's older module (verified in nixos-module.nix line ~7).
#
# ── Greeter ────────────────────────────────────────────────────────────────
# Noctalia-greeter is a greetd login greeter with a Noctalia look-and-feel.
# The greeter module sets `services.greetd.settings.default_session.command`
# to `noctalia-greeter-session`. After authentication, the greeter launches
# the user's chosen session (default: "niri") via its TOML config.
#
# ── Polkit ─────────────────────────────────────────────────────────────────
# NOTE: We do NOT enable polkit here. The niri NixOS module (imported by the
# host's per-host file) already sets `security.polkit.enable = true` and
# ships its own polkit-kde-agent via a systemd user service. Adding another
# agent here would conflict. If a host uses a non-niri compositor that
# doesn't bring its own polkit agent, the host override file should add one.
#
# ── gsettings schemas ──────────────────────────────────────────────────────
# Same XDG_DATA_DIRS prepending pattern as DMS module — for any child app
# that runs `gsettings get/set` under the graphical session.
#
# ── v5 beta caveat (verified 2026-08-10 from upstream README) ──────────────
# Noctalia v5 is currently in Beta. Configuration may shift between minor
# versions; pin via the flake input if stability matters more than features.
#
# ── Reversibility ──────────────────────────────────────────────────────────
# Removing this file (or un-importing config.nixos.modules.noctalia from
# a host) and running `nixos-rebuild switch` fully removes the shell.
# The flake inputs stay defined in flake.nix — they have zero cost when
# unused. Stage 2 cleanup removes them globally when every host migrates.
{ inputs, ... }:
{
  nixos.modules.noctalia =
    { lib, pkgs, ... }:

    {
      imports = [
        inputs.noctalia.nixosModules.default
        inputs.noctalia-greeter.nixosModules.default
      ];

      # gsettings schema paths — same pattern as DMS module. Noctalia is
      # non-Qt/non-GTK but child apps that use gsettings still need this.
      environment.sessionVariables.XDG_DATA_DIRS = lib.mkBefore [
        "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
        "${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}"
      ];

      # Noctalia shell defaults — every option explicitly written so a
      # host can flip one without re-listing the rest. mkDefault on the
      # recommended-services toggle so a host can disable the NM/UPower/
      # power-profiles defaults if it already provides them another way.
      programs.noctalia = {
        enable = true;
        systemd.enable = true;
        # target inherits upstream default (`graphical-session.target`).
        # The noctalia systemd user service is partOf this target, so it
        # starts under any graphical session (mango, niri, hyprland, ...).
        recommendedServices.enable = lib.mkDefault true;
      };

      # Noctalia-greeter (greetd frontend). Compositor session is selected
      # by the greeter at login time via its TOML config
      # (session.default = "niri"). The greeter module auto-enables greetd
      # and sets `services.greetd.settings.default_session.command` to
      # `noctalia-greeter-session`.
      programs.noctalia-greeter.enable = lib.mkDefault true;
    };
}