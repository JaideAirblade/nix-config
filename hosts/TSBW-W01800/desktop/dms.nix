# DankMaterialShell overrides for TSBW-W01800.
#
# The shared modules/wm/dms/dms.nix already imports the DMS + dank-greeter
# NixOS modules and sets sensible defaults (compositor=mango, calendarEvents
# via khal, etc.) via lib.mkDefault. This module overrides the host-specific
# bits:
#   - enableCalendarEvents = false (using DankCalendar instead of khal)
#   - imports DankCalendar NixOS module + enables it
#   - DMS systemd target/restartIfChanged
#   - i2c for DDC/CI brightness control
#   - Qt theming (qt6ct/qt5ct) for matugen-generated color schemes
{ inputs, ... }:
{
  nixos.hosts."TSBW-W01800" =
    { pkgs, lib, ... }: {
      imports = [
        inputs.dankcalendar.nixosModules.dank-calendar
      ];

      programs.dank-material-shell = {
        # DMS systemd settings — bind to graphical-session.target, which
        # mango's mango-session.target also requires, so DMS starts under
        # the primary compositor.
        systemd = {
          enable = true;
          # DMS refuses to start a second instance ("already running for this
          # session"), so restartIfChanged just stops+fails. Worse, stopping
          # dms.service during `nixos-rebuild switch` collapses
          # graphical-session.target (StopWhenUnneeded=yes,
          # RefuseManualStart=yes), which then prevents xdg-desktop-portal
          # (Requisite=graphical-session.target) from restarting — breaking
          # the portal on every switch that bumps the DMS store path.
          # Keep the running instance; it picks up the new path on reboot.
          restartIfChanged = false;
          target = lib.mkForce "graphical-session.target";
        };

        # Calendar: DankCalendar (dcal) replaces khal in DMS 1.5+
        # DMS auto-detects the dcal daemon via IPC at runtime
        enableCalendarEvents = lib.mkForce false; # Don't install khal — using DankCalendar instead

        # Plugins — declarative install via the dms-plugin-registry flake.
        # The registry exposes each plugin under
        # `programs.dank-material-shell.plugins.<id>.enable` and pre-fetches
        # the source via fetchFromGitHub (rev + hash in plugins-prefetch.json).
        # TSBW's 7 existing plugins (which were manually cloned into
        # ~/.config/DankMaterialShell/plugins) plus 4 new ones requested
        # 2026-08-20:
        #   sshConnections    — SSH host launcher (merdely/dms-plugins)
        #   usbManager        — USB device notifications (NordicsSys)
        #   emojiLauncher     — emoji & unicode picker (devnullvoid)
        #   quickCapture      — quick capture / clipboard (hthienloc)
        # Plugin set mirrors UwU's current install; pinned to the registry's
        # last-synced commits (currently 422e564, 2026-08-20). A few plugins
        # get a small upstream bump on first deploy (e.g. dmsThemeSync
        # 2607942 → 7bdd41d1, networkIndicator 619a552 → 81d948db) — those
        # are the latest upstream tokens and are the docs-recommended approach.
        plugins = {
          # TSBW-pre-existing plugins (7)
          animeCalendar.enable = true;
          audioInhibit.enable = true;
          batteryPlus.enable = true;
          calculator.enable = true;
          dmsThemeSync.enable = true;
          netbirdStatus.enable = true;
          networkIndicator.enable = true;
          # Newly added on 2026-08-20 (4)
          sshConnections.enable = true;
          usbManager.enable = true;
          emojiLauncher.enable = true;
          quickCapture.enable = true;
        };
      };

      # DankCalendar — standalone calendar app (replaces khal for DMS 1.5+)
      # https://github.com/AvengeMedia/dankcalendar
      programs.dank-calendar = {
        enable = true;
        systemd = {
          enable = true;
          # Same rationale as DMS above: stopping dcal.service mid-switch
          # collapses graphical-session.target and breaks xdg-desktop-portal.
          restartIfChanged = false;
          target = "graphical-session.target";
        };
      };

      # DankGreeter — primary compositor is mango.
      programs.dms-greeter = {
        enable = true;
        compositor.name = lib.mkForce "mango";
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
  ;
}
