# Mango → systemd session bridge for UwU-Server.
#
# Root-cause note (2026-08-15): `dms setup` rewrote
# ~/.config/mango/config.conf on 2026-07-15 and replaced the systemd startup
# lines (`dbus-update-activation-environment --systemd --all` +
# `systemctl --user start mango-session.target`) with a bare
# `exec-once=dms run`. That starts DMS as an unsupervised child of mango:
# when the DMS daemon+UI die (silent pair-kill, no coredump/OOM — see the
# 2026-08-13..15 crash streak), nothing respawns them and the panel stays
# dead until re-login. It also leaves graphical-session.target inactive,
# which breaks xdg-desktop-portal ("Dependency failed for Portal service").
#
# This target — together with the two exec-once lines restored in mango's
# config.conf — puts DMS back under dms.service (Restart=on-failure), so a
# crash becomes a ~2s blink and journald finally records the exit signal.
# Mirrors the proven setup in hosts/TSBW-W01800/desktop/{mango,dms}.nix.
{
  nixos.hosts."UwU-Server" =
    { lib, ... }: {
      # systemd user target for the mango session — activates
      # graphical-session.target, which pulls in dms.service (enabled via
      # programs.dank-material-shell.systemd.enable in modules/wm/dms).
      # Mango doesn't activate graphical-session.target on its own, so
      # mango's config starts this target via exec-once.
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

      programs.dank-material-shell = {
        systemd = {
          enable = true;
          # DMS refuses to start a second instance ("already running for this
          # session"), so a mid-switch restart just stops+fails. Worse,
          # stopping dms.service during `nixos-rebuild switch` collapses
          # graphical-session.target (StopWhenUnneeded=yes,
          # RefuseManualStart=yes), which then prevents xdg-desktop-portal
          # (Requisite=graphical-session.target) from restarting — breaking
          # the portal on every switch that bumps the DMS store path.
          # Keep the running instance; it picks up the new path on reboot.
          # (Same rationale as hosts/TSBW-W01800/desktop/dms.nix.)
          restartIfChanged = false;
          target = lib.mkForce "graphical-session.target";
        };
      };
    }
  ;
}
