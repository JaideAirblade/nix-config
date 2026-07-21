# DankMaterialShell overrides for TSBW-W01800.
#
# The shared modules/wm/dms/dms.nix already imports the DMS + dank-greeter
# NixOS modules and sets sensible defaults (compositor=mango, calendarEvents
# via khal, etc.) via lib.mkDefault. This module overrides the host-specific
# bits:
#   - compositor.name = "niri" (not mango)
#   - enableCalendarEvents = false (using DankCalendar instead of khal)
#   - imports DankCalendar NixOS module + enables it
#   - DMS systemd target/restartIfChanged
#   - i2c for DDC/CI brightness control
#   - Qt theming (qt6ct/qt5ct) for matugen-generated color schemes
#   - disable niri-flake's default polkit agent (DMS ships its own)
{inputs, pkgs, lib, ...}: {
  imports = [
    inputs.dankcalendar.nixosModules.dank-calendar
  ];

  programs.dank-material-shell = {
    # DMS systemd settings — bind to graphical-session.target, which niri
    # activates natively. Mango's mango-session.target also requires
    # graphical-session.target, so DMS starts under both compositors.
    systemd = {
      enable = true;
      restartIfChanged = true;
      target = lib.mkForce "graphical-session.target";
    };

    # Calendar: DankCalendar (dcal) replaces khal in DMS 1.5+
    # DMS auto-detects the dcal daemon via IPC at runtime
    enableCalendarEvents = lib.mkForce false;  # Don't install khal — using DankCalendar instead
  };

  # DankCalendar — standalone calendar app (replaces khal for DMS 1.5+)
  # https://github.com/AvengeMedia/dankcalendar
  programs.dank-calendar = {
    enable = true;
    systemd = {
      enable = true;
      restartIfChanged = true;
      target = "graphical-session.target";
    };
  };

  # DankGreeter — override compositor to niri (shared default is mango)
  programs.dms-greeter = {
    enable = true;
    compositor.name = lib.mkForce "niri";
    # Sync greeter theme with user's DMS settings
    configHome = "/home/jaide";
    # Save greeter logs for debugging. Use /var/log/dms-greeter.log
    # instead of /tmp — /tmp files survive reboots but can be owned by
    # a stale greeter UID after a rebuild shifts system user IDs,
    # causing a permission-denied crash loop on greeter startup.
    # /var/log is root-owned and the greeter session script runs as
    # the greeter user, so we pre-create the file via tmpfiles.
    logs = {
      save = true;
      path = "/var/log/dms-greeter.log";
    };
  };

  # Required by DMS for brightness control via DDC/CI (i2c bus access)
  # The nixpkgs dms-shell module sets this via mkDefault, but the flake module doesn't
  hardware.i2c.enable = true;

  # Qt theming — matugen (DMS dynamic theming) generates color configs for qt5ct/qt6ct,
  # but only if the binaries are on PATH. Without these, Qt app theming is silently skipped.
  # DMS defaults QT_QPA_PLATFORMTHEME to "gtk3" if unset; we override to "qt6ct" so Qt apps
  # actually load the matugen-generated color schemes.
  environment.systemPackages = with pkgs; [
    kdePackages.qt6ct
    libsForQt5.qt5ct
  ];
  environment.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "qt6ct";
    QT_QPA_PLATFORMTHEME_QT6 = "qt6ct";
  };

  # Use DMS's built-in polkit agent instead of niri-flake's default
  systemd.user.services.niri-flake-polkit.enable = false;

  # Pre-create the greeter log file AND fix stale ownership of greeter
  # state directories. When system user IDs shift between generations
  # (e.g. adding thermald), the greeter user gets a new UID but the
  # .cache/.local/.config dirs under /var/lib/dms-greeter retain the old
  # UID with 0700 perms — the greeter can't access them and crashes on
  # startup. The tmpfiles 'z' rule recursively fixes ownership on every
  # activation, so it self-heals even after UID shifts.
  systemd.tmpfiles.rules = [
    "f /var/log/dms-greeter.log 0666 greeter greeter -"
    "Z /var/lib/dms-greeter - greeter greeter -"
  ];
}