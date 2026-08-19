# Octarine DMS theme sync — keeps a GUI-created "DMS" custom theme's colours
# aligned with the live DMS palette.
#
# Octarine (Tauri/WebKitGTK note-taking app) stores custom themes per-workspace
# in <workspace>/.octarine/themes.json. The active theme selection lives in
# ~/.local/share/Octarine.app/.store.dat and WebKit localStorage.
#
# IMPORTANT: Octarine only recognises custom themes that were created through
# its own GUI (Settings → Theme Creator). Externally written themes are ignored.
# The user must create a custom theme named "DMS" through the GUI once.
#
# This module does NOT create themes or change the active theme selection.
# It only overwrites the CSS variables of the existing "DMS" custom theme in
# each workspace's themes.json with colours derived from the DMS Material
# palette. The user selects the DMS theme through Octarine's GUI; this module
# keeps its colours synced whenever DMS changes wallpaper or dark/light mode.
#
# Octarine loads themes.json at startup. If it's running, we kill it before
# writing (to prevent clobber on exit) and restart it after — same pattern as
# the Readest DMS theme module.
{
  nixos.modules.common =
    { pkgs, ... }:

    let
      syncScript = pkgs.writers.writePython3Bin "sync-octarine-dms-theme"
        {
          flakeIgnore = [ "E501" "E302" "E305" "F401" "E402" "E241" "W191" "E221" ];
        } ''
        import json
        import os
        import re
        import subprocess
        import sys
        import time
        from pathlib import Path

        HEX_COLOR = re.compile(r"^#[0-9a-fA-F]{6}$")
        THEME_NAME = "DMS"

        def require_color(colors, role):
            value = colors.get(role)
            if not isinstance(value, str) or not HEX_COLOR.fullmatch(value):
                raise ValueError(f"DMS palette is missing a valid {role!r} color")
            return value.lower()

        def active_mode(cache, gtk_colors):
            palettes = cache["colors"]
            gtk_background = gtk_colors.get("window_bg_color", "").lower()
            for mode in ("dark", "light"):
                if gtk_background == palettes[mode].get("background", "").lower():
                    return mode
            return "dark"

        # --- Read DMS palette cache -----------------------------------------
        home = Path.home()
        cache_home = Path(os.environ.get("XDG_CACHE_HOME", home / ".cache"))
        config_home = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
        data_home = Path(os.environ.get("XDG_DATA_HOME", home / ".local" / "share"))
        palette_path = cache_home / "DankMaterialShell" / "dms-colors.json"
        gtk_palette_path = config_home / "gtk-4.0" / "dank-colors.css"

        if not palette_path.exists():
            raise SystemExit(f"DMS palette not found at {palette_path}")

        with palette_path.open(encoding="utf-8") as f:
            cache = json.load(f)

        gtk_colors = {}
        if gtk_palette_path.exists():
            gtk_colors = {
                name: value
                for name, value in re.findall(
                    r"@define-color\\s+([a-z_]+)\\s+(#[0-9a-fA-F]{6})\\s*;",
                    gtk_palette_path.read_text(encoding="utf-8"),
                )
            }
        mode = active_mode(cache, gtk_colors)
        colors = cache["colors"][mode]

        # --- Build DMS color variables --------------------------------------
        def blend(c1, c2, ratio):
            r1, g1, b1 = int(c1[1:3], 16), int(c1[3:5], 16), int(c1[5:7], 16)
            r2, g2, b2 = int(c2[1:3], 16), int(c2[3:5], 16), int(c2[5:7], 16)
            r = round(r1 + (r2 - r1) * ratio)
            g = round(g1 + (g2 - g1) * ratio)
            b = round(b1 + (b2 - b1) * ratio)
            return f"#{r:02x}{g:02x}{b:02x}"

        def darken(color, ratio):
            return blend(color, "#000000", ratio)

        def alpha(color, aa):
            return color + aa

        bg          = require_color(colors, "background")
        surface_low = require_color(colors, "surface_container_low")
        surface     = require_color(colors, "surface_container")
        surface_hi  = require_color(colors, "surface_container_high")
        surface_top = require_color(colors, "surface_container_highest")
        on_surface  = require_color(colors, "on_surface")
        on_surf_var = require_color(colors, "on_surface_variant")
        outline     = require_color(colors, "outline")
        outline_var = require_color(colors, "outline_variant")
        primary     = require_color(colors, "primary")
        on_primary  = require_color(colors, "on_primary")
        prim_cont   = require_color(colors, "primary_container")
        error       = require_color(colors, "error")
        err_cont    = require_color(colors, "error_container")
        tert_cont   = require_color(colors, "tertiary_container")

        # In dark mode, primary is light (#bbc3ff) and on_primary is dark
        # (#001d93). For bg-accent (button fills) we need a dark background
        # with light text, so we use primary_container as the fill.
        if mode == "dark":
            accent_bg = prim_cont
            accent_text = primary
        else:
            accent_bg = primary
            accent_text = primary

        dms_variables = {
            "--color-text-primary":      on_surface,
            "--color-text-secondary":    on_surf_var,
            "--color-text-tertiary":     outline,
            "--color-text-placeholder":  on_surf_var,
            "--color-text-accent":       accent_text,
            "--color-text-link":         primary,
            "--color-text-error":        error,

            "--color-bg-primary":        surface_low,
            "--color-bg-intermediate":   surface,
            "--color-bg-secondary":      surface_hi,
            "--color-bg-tertiary":       surface_top,
            "--color-bg-hover":          surface_top,
            "--color-bg-accent":         accent_bg,
            "--color-bg-error":          err_cont,
            "--color-bg-kbd":            darken(surface_low, 0.15),
            "--color-bg-tooltip":        surface_top,
            "--color-app-sidebar":       darken(bg, 0.1),

            "--color-bg-mark":           alpha(tert_cont, "80"),
            "--color-bg-doc-link":       alpha(prim_cont, "20"),
            "--color-outline-primary":   alpha(primary, "80"),

            "--color-border-primary":    outline_var,
            "--color-border-secondary":  outline,
            "--color-border-accent":     accent_text,
            "--color-border-error":      error,

            "--color-icon":              on_surf_var,
            "--color-editor-heading":    on_surface,
            "--color-editor-body":       on_surface,
        }

        base_theme = "catppuccin-macchiato" if mode == "dark" else "catppuccin-latte"
        now_ms = int(time.time() * 1000)

        # --- Write DMS colours into the existing DMS theme (no kill/restart) ---
        # Unlike the previous approach, we do NOT kill Octarine. We write
        # themes.json in-place and rely on Octarine's filesystem watcher
        # (or the user's next theme switch) to pick up the changes.
        # If Octarine doesn't watch themes.json, the colours will apply
        # on next app launch.
        store_path = data_home / "Octarine.app" / ".store.dat"
        updated_count = 0

        if store_path.exists():
            with store_path.open(encoding="utf-8") as f:
                store = json.load(f)
            ws_registry = store.get("store", {}).get("config", {}).get("workspaces", {})

            for ws_uuid, ws_info in ws_registry.items():
                ws_path = Path(ws_info.get("path", ""))
                if not ws_path.exists():
                    print(f"WARNING: workspace path does not exist: {ws_path}", file=sys.stderr)
                    continue

                themes_file = ws_path / ".octarine" / "themes.json"
                if not themes_file.exists():
                    print(f"WARNING: no themes.json in {ws_path}, skipping", file=sys.stderr)
                    continue

                with themes_file.open(encoding="utf-8") as f:
                    themes = json.load(f)

                # Find the DMS theme by name
                target = next((t for t in themes if t.get("name") == THEME_NAME), None)
                if target is None:
                    print(f"WARNING: no '{THEME_NAME}' custom theme in {ws_path}. "
                          f"Create it via Settings → Theme Creator in Octarine.",
                          file=sys.stderr)
                    continue

                # Overwrite only the variables, baseTheme, dark, and modified.
                # Preserve id, name, created.
                target["variables"] = dms_variables
                target["baseTheme"] = base_theme
                target["dark"] = (mode == "dark")
                target["modified"] = now_ms

                tmp = themes_file.with_suffix(".json.tmp")
                with tmp.open("w", encoding="utf-8") as f:
                    json.dump(themes, f, indent=2)
                    f.write("\n")
                tmp.replace(themes_file)
                updated_count += 1
        else:
            print("WARNING: Octarine .store.dat not found, skipping", file=sys.stderr)

        print(f"Synced Octarine DMS theme colours (mode={mode}, "
              f"workspaces={updated_count})")
      '';

    in
    {
      systemd.user.services.octarine-dms-theme-sync = {
        description = "Sync Octarine DMS theme colours with DankMaterialShell";
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
          exec ${syncScript}/bin/sync-octarine-dms-theme
        '';
      };

      systemd.user.paths.octarine-dms-theme-sync = {
        description = "Watch DMS palette changes for Octarine";
        unitConfig.ConditionUser = "jaide";
        wantedBy = [ "default.target" ];
        pathConfig = {
          PathChanged = [
            "%h/.cache/DankMaterialShell"
            "%h/.config/gtk-4.0"
          ];
        };
      };
    };
}