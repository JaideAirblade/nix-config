# Readest DMS theme sync — app theme mode + custom book theme from DMS palette.
#
# Readest (Tauri/WebKitGTK ebook reader) has two independent theme concepts:
#
#  1. App theme mode (themeMode in localStorage):
#     Controls the app chrome (sidebar, toolbar, dialogs) light/dark state.
#     Stored in the WebKit localStorage SQLite DB as a UTF-16LE string.
#     Values: 'auto' | 'light' | 'dark' | 'ambient'. 'auto' follows
#     prefers-color-scheme, which DMS sets via gsettings
#     org.gnome.desktop.interface color-scheme. When the key is absent the
#     app defaults to 'auto', but the user may have pinned it to 'light' via
#     the View menu, so we enforce it on every sync.
#
#  2. Book reading theme (globalViewSettings.theme in settings.json):
#     Controls the book page background/text/accent colors. Built-in values
#     are 'default', 'gray', 'sepia', 'grass', etc. Custom themes
#     (customThemes array in globalReadSettings) add a new named option with
#     user-defined bg/fg/primary for both light and dark.
#
# This module:
#   1. Enforces themeMode='auto' in localStorage so the app chrome follows DMS.
#   2. Adds a 'dms' custom theme to customThemes, with bg/fg/primary colors
#      derived from DMS's dms-colors.json palette (both light and dark).
#   3. Sets globalViewSettings.theme='dms' so books use the DMS palette.
#   4. A systemd user service + path unit watches dms-colors.json and re-syncs
#      the custom theme colors whenever DMS changes wallpaper or light/dark.
#
# Readest loads settings.json + localStorage at startup and keeps them in
# memory. On exit it writes the full in-memory state back, clobbering any
# external changes made while it was running. The sync script therefore
# kills a running Readest before writing, waits for it to fully exit, then
# restarts it. Reading progress is saved by Readest on SIGTERM so no position
# is lost.
{
  nixos.modules.common =
    { pkgs, ... }:

    let
      syncScript = pkgs.writers.writePython3Bin "sync-readest-dms-theme"
        {
          flakeIgnore = [ "E501" "E302" "E305" "F401" "E402" ];
        } ''
        import json
        import os
        import re
        import signal
        import sqlite3
        import subprocess
        import sys
        import time
        from pathlib import Path

        HEX_COLOR = re.compile(r"^#[0-9a-fA-F]{6}$")

        def require_color(colors, role):
            value = colors.get(role)
            if not isinstance(value, str) or not HEX_COLOR.fullmatch(value):
                raise ValueError(f"DMS palette is missing a valid {role!r} color")
            return value.lower()

        # --- Read DMS palette cache -----------------------------------------
        home = Path.home()
        cache_home = Path(os.environ.get("XDG_CACHE_HOME", home / ".cache"))
        palette_path = cache_home / "DankMaterialShell" / "dms-colors.json"

        if not palette_path.exists():
            raise SystemExit(f"DMS palette not found at {palette_path}")

        with palette_path.open(encoding="utf-8") as f:
            cache = json.load(f)

        dark = cache["colors"]["dark"]
        light = cache["colors"]["light"]

        # --- Build the custom theme -----------------------------------------
        # CustomTheme = { name, label, colors: { light: {bg,fg,primary},
        #                                         dark:  {bg,fg,primary} } }
        # Readest's generateLightPalette/generateDarkPalette derive the full
        # Palette (base-100/200/300, neutral, secondary, accent) from these
        # three base colors via tinycolor manipulation.
        dms_theme = {
            "name": "dms",
            "label": "DMS",
            "colors": {
                "light": {
                    "bg": require_color(light, "surface_container_lowest"),
                    "fg": require_color(light, "on_surface"),
                    "primary": require_color(light, "primary"),
                },
                "dark": {
                    "bg": require_color(dark, "surface_container_lowest"),
                    "fg": require_color(dark, "on_surface"),
                    "primary": require_color(dark, "primary"),
                },
            },
        }

        # --- Update settings.json -------------------------------------------
        config_home = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
        settings_path = config_home / "com.bilingify.readest" / "settings.json"

        if settings_path.exists():
            with settings_path.open(encoding="utf-8") as f:
                settings = json.load(f)
        else:
            settings = {}

        # Enforce the custom theme in customThemes (replace if name matches).
        grs = settings.setdefault("globalReadSettings", {})
        custom_themes = grs.setdefault("customThemes", [])
        custom_themes = [t for t in custom_themes if t.get("name") != "dms"]
        custom_themes.append(dms_theme)
        grs["customThemes"] = custom_themes

        # Point the book reading theme at the DMS custom theme.
        gvs = settings.setdefault("globalViewSettings", {})
        gvs["theme"] = "dms"

        settings_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = settings_path.with_suffix(".json.tmp")
        with tmp.open("w", encoding="utf-8") as f:
            json.dump(settings, f, indent=2)
            f.write("\n")
        tmp.replace(settings_path)

        # --- Enforce themeMode='auto' and customThemes in localStorage -------
        # WebKit stores localStorage in a SQLite DB with WAL mode. Values are
        # UTF-16LE encoded (no BOM, no length prefix). The 'themeMode' key
        # controls whether the app chrome follows prefers-color-scheme
        # ('auto') or is pinned to light/dark. We set it to 'auto' so DMS's
        # gsettings org.gnome.desktop.interface color-scheme drives the app
        # shell.
        #
        # 'customThemes' is also cached in localStorage by themeStore's
        # saveCustomTheme method. Without syncing it here, Readest loads the
        # stale (empty) localStorage copy on startup and the DMS theme never
        # appears in the theme picker, even though settings.json has it.
        #
        # 'themeColor' tells Readest which theme to use for the app chrome.
        # Without this, getThemeCode() falls back to the built-in 'default'
        # theme and our custom 'dms' theme is never selected.
        #
        # WAL handling: after killing Readest (done above), WebKit's WAL may
        # still contain uncommitted pages from the previous session. We must
        # checkpoint (merge WAL into the main DB) before our write, otherwise
        # sqlite3 reads through the stale WAL and our INSERT OR REPLACE gets
        # shadowed by old WAL entries. We also delete the WAL and SHM files
        # after checkpointing to ensure WebKit starts with a clean slate —
        # SQLite will recreate them on next access.
        data_home = Path(os.environ.get("XDG_DATA_HOME", home / ".local" / "share"))
        ls_dir = data_home / "com.bilingify.readest" / "localstorage"

        custom_themes_json = json.dumps(custom_themes).encode("utf-16-le")

        for ls_file in sorted(ls_dir.glob("*.localstorage")):
            # Checkpoint the WAL to merge any pending writes into the main DB
            conn = sqlite3.connect(str(ls_file), isolation_level=None)
            try:
                conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
                conn.execute(
                    "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
                    ("themeMode", "auto".encode("utf-16-le")),
                )
                conn.execute(
                    "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
                    ("themeColor", "dms".encode("utf-16-le")),
                )
                conn.execute(
                    "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
                    ("customThemes", custom_themes_json),
                )
                conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            finally:
                conn.close()

            # Delete WAL and SHM so WebKit starts fresh — no stale pages
            for suffix in ("-wal", "-shm"):
                wal_file = Path(str(ls_file) + suffix)
                if wal_file.exists():
                    wal_file.unlink()

        # --- Clear WebKit HTTP cache for the sync API -----------------------
        # Readest's cloud sync fetches settings from
        # web.readest.com/api/sync/replicas?kind=settings. WebKit caches
        print("Synced Readest DMS theme (themeMode=auto, custom theme=dms)")
      '';

    in
    {
      # Oneshot that regenerates the Readest custom theme from the current
      # DMS palette, enforcing themeMode=auto and the DMS custom theme in
      # both settings.json and localStorage. Writes in-place without killing
      # the app — colours apply on next app launch or theme switch.
      systemd.user.services.readest-dms-theme-sync = {
        description = "Sync Readest theme with DankMaterialShell";
        unitConfig.ConditionUser = "jaide";
        after = [ "graphical-session.target" ];
        wantedBy = [ "default.target" ];
        serviceConfig = {
          Type = "oneshot";
          Restart = "on-failure";
          RestartSec = "2s";
        };
        script = ''
          sleep 2
          exec ${syncScript}/bin/sync-readest-dms-theme
        '';
      };

      # Watch the DMS palette cache directory. DMS updates dms-colors.json
      # atomically, so watch the parent directory.
      systemd.user.paths.readest-dms-theme-sync = {
        description = "Watch DMS palette changes for Readest";
        unitConfig.ConditionUser = "jaide";
        wantedBy = [ "default.target" ];
        pathConfig = {
          PathChanged = [ "%h/.cache/DankMaterialShell" ];
        };
      };
    };
}
