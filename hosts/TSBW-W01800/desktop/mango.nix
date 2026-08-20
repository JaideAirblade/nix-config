# MangoWC — Wayland compositor based on dwl
# https://github.com/mangowm/mango
#
# Mango is the PRIMARY compositor on this host.
# The shared modules/wm/mango already imports inputs.mangowm.nixosModules.mango
# and enables programs.mango. We only need the mango-session target so
# DMS (and other graphical-session services) auto-start when mango launches.
{ pkgs, ... }:
{
  nixos.hosts."TSBW-W01800" =
    { pkgs, ... }: {
      # systemd user target for mango session — needed so DMS (and other
      # graphical-session services) auto-start when mango launches.
      # Mango doesn't activate graphical-session.target on its own, so we
      # create a dedicated target and have mango's config start it.
      # See: https://danklinux.com/docs/dankmaterialshell/installation#mangowc
      systemd.user.targets.mango-session = {
        description = "MangoWC Session Target";
        requires = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        unitConfig = {
          AllowIsolate = true;
        };
      };

      # Mango is launched by greetd (not as a systemd service), so the systemd
      # user manager never inherits WAYLAND_DISPLAY, XDG_RUNTIME_DIR,
      # XDG_CURRENT_DESKTOP, etc. Services that depend on
      # graphical-session.target (xdg-desktop-portal-wlr, DMS, dcal) need
      # these to be in the systemd user environment — especially
      # xdg-desktop-portal-wlr, which fails with "wayland: failed to connect
      # to display" if WAYLAND_DISPLAY is absent or stale.
      #
      # We install a small script that imports the live compositor
      # environment into the systemd user manager and starts
      # mango-session.target. Mango's config.conf runs it via exec-once.
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "mango-session-start" ''
          # Import the compositor's environment into the systemd user
          # manager so that user services spawned by systemd (portals,
          # DMS, dcal) inherit the correct WAYLAND_DISPLAY, XDG_RUNTIME_DIR,
          # XDG_CURRENT_DESKTOP, etc.
          systemctl --user import-environment \
            WAYLAND_DISPLAY \
            XDG_RUNTIME_DIR \
            XDG_CURRENT_DESKTOP \
            XDG_SESSION_TYPE

          # Start the mango session target, which pulls in
          # graphical-session.target. Portal services and DMS depend on
          # graphical-session.target, so they come up automatically once
          # it's active.
          systemctl --user start mango-session.target
        '')
      ];
    }
  ;
}