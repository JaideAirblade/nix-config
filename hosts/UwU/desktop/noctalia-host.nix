# UwU-specific Noctalia + niri overrides.
#
# Auto-discovered by `collectModules ./hosts "hosts"` (see flake.nix ~line 174).
# This file is host-scoped via the `nixos.hosts."UwU"` flake-parts namespace —
# changes here never affect TSBW-W01800, UwU-Server, or other hosts.
#
# ── What this file does ────────────────────────────────────────────────────
# 1. Disables the DMS / mango / dms-greeter packages that `nixos.modules.common`
#    pulls in via modules/wm/{dms,mango}/dms.nix — they would otherwise run
#    on UwU in parallel with noctalia and clash.
# 2. Enables `programs.niri` from nixpkgs's built-in Niri module
#    (nixos/modules/programs/wayland/niri.nix). Niri registers itself as a
#    Wayland session via services.displayManager.sessionPackages, so the
#    noctalia-greeter discovers it automatically and offers it as the
#    session to launch after authentication.
#
# ── Why lib.mkForce on the disables ────────────────────────────────────────
# `programs.dank-material-shell.enable = true` and `programs.mango.enable = true`
# are set in `modules/wm/dms/dms.nix` / `modules/wm/mango/mango.nix` without
# mkDefault — they're hard `true`. To override a hard `true` on a host without
# editing the shared role modules, we use `lib.mkForce false` here.
#
# ── Why nixpkgs#niri (not niri-flake) ──────────────────────────────────────
# github:sodiboo/niri-flake is currently broken on this nixpkgs revision
# because its `make-niri` function asserts
# `libdisplay-info_0_2.version == "0.2.0"`, and libdisplay-info_0_2 has been
# removed from nixpkgs (replaced by _0_3 / 0.4.0). The niri-flake's 10 most
# recent commits are all "Update flake.lock" with no actual fix. We use
# nixpkgs's built-in `programs.niri` module instead, which uses pkgs.niri
# (currently 26.04) built against the current libdisplay-info. See the
# comment in flake.nix for the full rationale.
#
# When the niri-flake fixes the assertion, swap back by:
#   1. Re-adding `niri.url = "github:sodiboo/niri-flake"` to flake.nix inputs
#   2. Adding `imports = [ inputs.niri.nixosModules.niri ];` here
# The option names are compatible.
#
# ── Reversibility ──────────────────────────────────────────────────────────
# Removing this file (and the matching `config.nixos.modules.noctalia` line
# in hosts/UwU/default.nix) and re-running `nixos-rebuild switch` brings UwU
# back to DMS/mango with a single revert commit. The DMS/mango flake inputs
# stay defined in flake.nix — they have zero cost when unused by any host.
#
# ── Session flow at login (for future debugging) ──────────────────────────
#  1. greetd starts noctalia-greeter (set by noctalia-greeter module:
#     services.greetd.settings.default_session.command =
#       "${noctalia-greeter}/bin/noctalia-greeter-session")
#  2. user authenticates via the greeter
#  3. greeter reads its TOML config (session.default) and launches niri
#     (niri registers as a Wayland session via its .desktop file, which
#     the nixpkgs niri module wires into services.displayManager.sessionPackages)
#  4. niri starts → activates graphical-session.target
#  5. noctalia.service (bound to graphical-session.target via partOf) starts
#     automatically and renders the bar / widgets on top of the niri session
_:
{
  nixos.hosts."UwU" =
    { lib, ... }:
    {
      # ── Disable what `common` would otherwise pull in ──────────────────
      programs.dank-material-shell.enable = lib.mkForce false;
      programs.mango.enable = lib.mkForce false;
      programs.dms-greeter.enable = lib.mkForce false;

      # ── Enable niri (nixpkgs built-in module) ────────────────────────
      # The nixpkgs niri module (nixos/modules/programs/wayland/niri.nix)
      # handles: sessionPackages (so greeter finds niri), xdg portal +
      # xdg-desktop-portal-gnome, gnome-keyring, dbus + nautilus for the
      # file chooser, default session pinning, and a properly-configured
      # systemd user service. No further wiring needed here.
      programs.niri.enable = true;
    };
}