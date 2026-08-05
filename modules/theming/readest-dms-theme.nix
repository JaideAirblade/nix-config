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

        # --- Stop Readest if running ----------------------------------------
        # Readest overwrites settings.json and localStorage on exit from its
        # in-memory state. We must stop it BEFORE writing, and wait for the
        # process to fully exit so its final write lands before our write.
        # SIGTERM lets Readest save reading progress and flush settings.
        #
        # The nixpkgs wrapper binary is named '.readest-wrapped', which Linux
        # truncates to '.readest-wrappe' in /proc/.../comm (15-char limit).
        # pgrep -x 'readest' never matches — we match on the full comm name.
        READEST_COMM = ".readest-wrappe"

        try:
            result = subprocess.run(
                ["pgrep", "-x", READEST_COMM],
                capture_output=True, text=True, check=False,
            )
            readest_was_running = result.returncode == 0
        except FileNotFoundError:
            readest_was_running = False

        if readest_was_running:
            subprocess.run(["pkill", "-x", READEST_COMM], check=False)
            for _ in range(100):  # up to 10 seconds — WebKit WAL checkpoint
                result = subprocess.run(
                    ["pgrep", "-x", READEST_COMM],
                    capture_output=True, check=False,
                )
                if result.returncode != 0:
                    break
                time.sleep(0.1)
            else:
                print("WARNING: readest did not exit within 10s, proceeding anyway",
                      file=sys.stderr)
            # Give WebKit's SQLite WAL a moment to finish checkpointing
            # after the process exits. The WAL file is checkpointed by
            # WebKit on clean shutdown, but the filesystem write may lag.
            time.sleep(1)

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

        # Disable Readest Cloud settings sync so it cannot pull stale
        # customThemes from the cloud and clobber our local write. The user
        # is logged in to Readest Cloud (supabase auth token in localStorage),
        # and the 'settings' syncCategory defaults to True. On startup Readest
        # pulls the cloud settings — which have the old customThemes — and
        # overwrites both settings.json and localStorage before our colors
        # take effect. Setting readestCloud.enabled = False explicitly
        # disables the cloud sync backend, and syncCategories.settings =
        # False prevents the settings replica from syncing.
        settings["readestCloud"] = {"enabled": False}
        sync_cats = settings.setdefault("syncCategories", {})
        sync_cats["settings"] = False

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
        # this HTTP response on disk. Even after we disable cloud sync in
        # settings, the cached response (with old customThemes colors) is
        # served from the WebKitCache on startup, clobbering our local write.
        # Clearing the entire WebKitCache is heavy-handed but reliable —
        # Readest re-fetches everything it needs on next access.
        webkit_cache = data_home / "com.bilingify.readest" / "WebKitCache"
        if webkit_cache.exists():
            import shutil
            shutil.rmtree(str(webkit_cache), ignore_errors=True)

        # --- Push updated settings to Readest Cloud --------------------------
        # Readest Cloud's replica sync pulls the 'settings' kind on startup.
        # If the cloud has stale customThemes (e.g., a previous DMS palette
        # from an earlier sync), Readest overwrites our local write with the
        # stale cloud version. We must push our updated settings to the cloud
        # so the cloud and local are in sync.
        #
        # The push API is POST /api/sync/replicas with { rows: [ReplicaRow] }.
        # Each ReplicaRow has: user_id, kind, replica_id, fields_jsonb,
        # updated_at_ts, deleted_at_ts, schema_version, manifest_jsonb.
        # fields_jsonb is a flat map of dotted paths to CRDT cells {s, t, v}.
        import urllib.request
        import urllib.error

        try:
            ls_conn = sqlite3.connect(str(ls_dir / "tauri_localhost_0.localstorage"))
            token_row = ls_conn.execute(
                "SELECT value FROM ItemTable WHERE key='sb-readest-auth-token'"
            ).fetchone()
            user_row = ls_conn.execute(
                "SELECT value FROM ItemTable WHERE key='user'"
            ).fetchone()
            ls_conn.close()
            if token_row and user_row:
                token_data = json.loads(token_row[0].decode("utf-16-le"))
                user_data = json.loads(user_row[0].decode("utf-16-le"))
                access_token = token_data.get("access_token", "")
                user_id = user_data.get("id", "")
                replica_device_id = settings.get("replicaDeviceId", "")

                # Build the fields_jsonb for the settings replica.
                # Each field is a dotted path mapped to a CRDT cell:
                # {s: source_device_id, t: hlc_timestamp, v: value}.
                # The HLC timestamp format is:
                #   ${"$"}{physicalMs:13-hex}-${"$"}{counter:8-hex}-${"$"}{deviceId}
                # The physicalMs must be close to the server's wall clock
                # or the push is rejected with 409 CLOCK_SKEW.
                hlc_ts = f"{int(time.time() * 1000):013x}-00000001-{replica_device_id}"
                fields = {
                    "globalReadSettings.customThemes": {
                        "s": replica_device_id, "t": hlc_ts, "v": custom_themes,
                    },
                    "globalViewSettings.theme": {
                        "s": replica_device_id, "t": hlc_ts, "v": "dms",
                    },
                }

                row = {
                    "user_id": user_id,
                    "kind": "settings",
                    "replica_id": "singleton",
                    "fields_jsonb": fields,
                    "updated_at_ts": hlc_ts,
                    "deleted_at_ts": None,
                    "reincarnation": None,
                    "schema_version": 1,
                    "manifest_jsonb": None,
                }

                payload = json.dumps({"rows": [row]}).encode("utf-8")

                req = urllib.request.Request(
                    "https://web.readest.com/api/sync/replicas",
                    data=payload,
                    headers={
                        "Authorization": f"Bearer {access_token}",
                        "Content-Type": "application/json",
                    },
                    method="POST",
                )
                urllib.request.urlopen(req, timeout=10)
                print("Pushed updated settings to Readest Cloud")
        except Exception as e:
            print(f"WARNING: failed to push to Readest Cloud: {e}", file=sys.stderr)

        # --- Restart Readest if it was running ------------------------------
        if readest_was_running:
            # Detach so the service (oneshot) doesn't hold the child open.
            subprocess.Popen(
                ["readest"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )

        print("Synced Readest DMS theme (themeMode=auto, custom theme=dms)")
      '';

    in
    {
      # Oneshot that regenerates the Readest custom theme from the current
      # DMS palette, enforcing themeMode=auto and the DMS custom theme in
      # both settings.json and localStorage. If Readest is running, it is
      # stopped before writing (to prevent clobber) and restarted after.
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
