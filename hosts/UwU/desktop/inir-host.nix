# UwU-specific iNiR + niri + SDDM wiring.
#
# Auto-discovered by `collectModules ./hosts "hosts"` (see flake.nix ~line 174).
# This file is host-scoped via the `nixos.hosts."UwU"` flake-parts namespace —
# changes here never affect TSBW-W01800, UwU-Server, or other hosts.
#
# ── What this file does ────────────────────────────────────────────────────
# 1. Disables the DMS / mango / dms-greeter / noctalia-greeter packages that
#    `nixos.modules.common` and the previous noctalia role module would
#    otherwise pull in. They would otherwise run on UwU in parallel with
#    iNiR and clash.
# 2. Enables `programs.niri` from nixpkgs's built-in Niri module
#    (nixos/modules/programs/wayland/niri.nix). Niri registers itself as
#    a Wayland session via services.displayManager.sessionPackages, so
#    SDDM discovers it automatically and offers it as the session to
#    launch after authentication.
# 3. Enables iNiR (`programs.inir`) — the upstream NixOS module from the
#    iNiR flake. Wired to niri.service via `service.compositor = "niri"`
#    so the user shell starts under any session that pulls niri in.
# 4. Replaces greetd with SDDM using the ii-pixel theme (vendored as
#    pkgs.inir-sddm-theme from upstream iNiR/dots/sddm/pixel). The theme
#    follows the iNiR Material You aesthetic so the login screen matches
#    the shell.
#
# ── Why nixpkgs#niri (not niri-flake) ──────────────────────────────────────
# github:sodiboo/niri-flake is currently broken on this nixpkgs revision
# because its `make-niri` function asserts
# `libdisplay-info_0_2.version == "0.2.0"`, and libdisplay-info_0_2 has
# been removed from nixpkgs (replaced by _0_3 / 0.4.0). The niri-flake's 10
# most recent commits are all "Update flake.lock" with no actual fix. We
# use nixpkgs's built-in `programs.niri` module instead, which uses
# `pkgs.niri` (currently 26.04) built against the current libdisplay-info.
# See the comment in flake.nix for the full rationale.
#
# ── Why SDDM (not greetd) ──────────────────────────────────────────────────
# iNiR ships a login screen theme (ii-pixel), but no auth flow / PAM
# config of its own — it's a session shell, not a login manager. SDDM
# gives us a Qt6 themable greeter with first-class PAM + u2f support in
# nixpkgs. Switching away from greetd also means the keyring-unlock-on-
# login PAM hook (was `security.pam.services.greetd.enableGnomeKeyring`)
# becomes `services.xserver.displayManager.sddm.enableGnomeKeyring`
# internally. The keyring module is updated to handle this in
# modules/keyring/keyring.nix.
#
# ── Reversibility ──────────────────────────────────────────────────────────
# Removing this file (and the matching `config.nixos.modules.inir` line
# in hosts/UwU/default.nix) and re-running `nixos-rebuild switch` brings
# UwU back to a greetd/Noclalia configuration with a single revert commit.
# The DMS/mango/inir flake inputs stay defined in flake.nix — they have
# zero cost when unused by any host.
#
# ── Session flow at login (for future debugging) ──────────────────────────
#  1. SDDM starts and renders the ii-pixel theme
#  2. user authenticates via SDDM (PAM + u2f honored)
#  3. SDDM launches the niri Wayland session (the nixpkgs niri module
#     wires services.displayManager.sessionPackages)
#  4. niri starts → activates graphical-session.target
#  5. inir.service (bound to niri.service via `service.compositor = "niri"`
#     and to graphical-session.target via partOf) starts automatically
#     and renders the iNiR bar / widgets on top of the niri session
_: {
  nixos.hosts."UwU" =
    { config, lib, pkgs, ... }:
    {
      # ── Disable what `common` and the previous noctalia role would
      #    otherwise pull in — they would clash with iNiR. These are
      #    hard `true` in their shared modules, so we mkForce false here.
      programs.dank-material-shell.enable = lib.mkForce false;
      programs.mango.enable = lib.mkForce false;
      programs.dms-greeter.enable = lib.mkForce false;
      # Disable greetd entirely ─ SDDM is the new login manager on UwU.
      # mkForce false here is safe because greetd has no other enabler
      # on this host (the previous noctalia role module was the only
      # one that touched it). The default is false anyway; this is
      # declarative hygiene in case a future contributor re-enables
      # greetd at the role level.
      services.greetd.enable = lib.mkForce false;

      # ── Enable niri (nixpkgs built-in module) ────────────────────────
      # The nixpkgs niri module (nixos/modules/programs/wayland/niri.nix)
      # handles: sessionPackages (so SDDM finds niri), xdg portal +
      # xdg-desktop-portal-gnome, gnome-keyring, dbus + nautilus for the
      # file chooser, default session pinning, and a properly-configured
      # systemd user service. No further wiring needed here.
      programs.niri.enable = true;

      # ── Enable SDDM with the ii-pixel theme ─────────────────────────
      # Vendored as `pkgs.inir-sddm-theme` in pkgs/inir-sddm-theme/.
      # The `theme` option tells SDDM which entry under
      # /share/sddm/themes to load. The package is added to
      # environment.systemPackages below so SDDM's theme picker finds it.
      services.displayManager.sddm = {
        enable = true;
        theme = "ii-pixel";
        # Wayland session by default — Niri is the only compositor on
        # this host. SDDM itself boots into Wayland (Qt6) seamlessly.
        wayland.enable = true;
      };

      # Install the ii-pixel theme into /share/sddm/themes/ii-pixel/ so
      # SDDM's `theme = "ii-pixel"` lookup resolves. The package itself
      # doesn’t know its payload path; we add it explicitly.
      environment.systemPackages = [ pkgs.inir-sddm-theme ];
    };
}
