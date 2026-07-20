# MangoWC — Wayland compositor based on dwl
# https://github.com/mangowm/mango
#
# Mango is the secondary compositor on this host (niri is primary).
# The shared modules/wm/mango already imports inputs.mangowm.nixosModules.mango
# and enables programs.mango. We only need the mango-session target so
# DMS (and other graphical-session services) auto-start when mango launches.
{...}: {
  # systemd user target for mango session — needed so DMS (and other
  # graphical-session services) auto-start when mango launches.
  # Mango doesn't activate graphical-session.target on its own, so we
  # create a dedicated target and have mango's config start it.
  # See: https://danklinux.com/docs/dankmaterialshell/installation#mangowc
  systemd.user.targets.mango-session = {
    description = "MangoWC Session Target";
    requires = ["graphical-session.target"];
    after = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    unitConfig = {
      AllowIsolate = true;
    };
  };
}