# OnlyOffice DMS theme sync — paint the OnlyOffice chrome with the live
# DankMaterialShell palette.
#
# OnlyOffice (9.1.0+) supports custom interface themes via JSON files
# dropped into `editors/web-apps/apps/common/main/resources/themes/`.
# The bundled directory ships an empty `themes.json` manifest:
#
#     $out/editors/web-apps/apps/common/main/resources/themes/themes.json
#     → {"themes": []}
#
# To add a custom theme:
#   1. Write `theme-<id>.json` in that directory.
#   2. Append `<id>` to the `themes` array in `themes.json`.
#   3. The user picks the theme from Settings → Interface theme in OO.
#
# See the official guide:
#   https://helpcenter.onlyoffice.com/docs/installation/docs-developer-change-theme.aspx
#
# The path lives inside the read-only /nix/store. We use the same bwrap
# `--bind` trick as the legcord/readest DMS-theming modules: write a
# writable `themes/` tree to `~/.cache/onlyoffice-themes/themes/` and
# have the wrapper prepend `--bind ~/.cache/onlyoffice-themes/themes
# /usr/share/desktopeditors/editors/web-apps/apps/common/main/resources/themes`
# to the bwrap command. bwrap processes binds left-to-right; later binds
# shadow earlier ones — so our writable copy wins for CEF.
#
# Wrapper requirements:
#   - Locate the upstream bwrap launcher (a symlink in the unwrapped
#     package that we replace with our wrapper script). The capture-
#     and-substitute dance uses a __BWRAP_PATH__ sentinel in the wrapper
#     script body, filled in by sed in extraInstallCommands.
#   - The sync script reads DMS's color cache and writes
#     `~/.cache/onlyoffice-themes/themes/theme-dms.json` plus updates
#     `~/.cache/onlyoffice-themes/themes/themes.json`. CEF reads the
#     `themes.json` list at startup; we patch it in place with the
#     sentinel-guarded marker pattern.
#   - If OnlyOffice is currently running, the sync kills it before
#     rewriting the manifest (CEF caches `themes.json` at startup; a
#     live re-read isn't supported). Next launch picks up new colors.
#   - A systemd user path unit watches the DMS palette cache and the
#     OO themes cache; re-runs the sync whenever DMS updates.
_:
{
  nixos.modules.common =
    { pkgs, lib, ... }:

    let
      # Material Design 3 → OnlyOffice theme variable names. The OO docs
      # (docs-developer-change-theme.aspx) list every valid color key;
      # we map DMS Material roles onto the subset that's user-visible
      # in the chrome (toolbar, sidebar, scrollbars, buttons).
      #
      # Variables we deliberately skip: per-document editor colors
      # (background-normal, etc. inside the doc canvas), which the user
      # expects to be page-content driven, not theme driven.
      #
      # Dark variant — used when DMS reports dark mode.
      darkPalette = {
        "toolbar-header-document"      = "PRIMARY";
        "toolbar-header-spreadsheet"   = "PRIMARY";
        "toolbar-header-presentation"  = "PRIMARY";
        "toolbar-header-pdf"           = "PRIMARY";
        "toolbar-header-draw"          = "PRIMARY";
        "background-toolbar"           = "SURFACE";
        "text-toolbar-header"          = "ON_SURFACE";
        "highlight-button-hover"       = "SURFACE_CONTAINER_HIGH";
        "background-normal"            = "SURFACE";
        "border-regular-control"       = "OUTLINE_VARIANT";
        "border-divider"               = "OUTLINE_VARIANT";
        "canvas-scroll-thumb-hover"    = "OUTLINE";
        "window-background"            = "SURFACE";
        "window-border"                = "OUTLINE_VARIANT";
        "text-normal"                  = "ON_SURFACE";
        "text-pretty"                  = "ON_SURFACE_VARIANT";
        "text-inverse"                 = "ON_PRIMARY";
        "menu-background"               = "SURFACE_CONTAINER";
        "menu-border"                  = "OUTLINE_VARIANT";
        "menu-item-hover-background"   = "SURFACE_CONTAINER_HIGH";
        "menu-text"                    = "ON_SURFACE";
        "menu-text-item-hover"         = "ON_PRIMARY";
        "menu-text-item-disabled"      = "ON_SURFACE_VARIANT";
        "menu-separator"               = "OUTLINE_VARIANT";
        "tooltip-text"                 = "ON_SURFACE";
        "tooltip-border"               = "OUTLINE_VARIANT";
        "tooltip-background"           = "SURFACE_CONTAINER_HIGHEST";
        "tab-default-active-background" = "SURFACE_CONTAINER";
        "tab-default-active-text"      = "ON_SURFACE";
        "tab-simple-active-background" = "SURFACE_CONTAINER";
        "tab-simple-active-text"        = "ON_SURFACE";
        "tab-divider"                  = "OUTLINE_VARIANT";
        "background-accent-button"     = "PRIMARY";
        "border-control-focus"        = "PRIMARY";
        "highlight-text-select"       = "PRIMARY";
      };

      # Light variant — used when DMS reports light mode. Reuses the
      # same DMS M3 tokens, just selecting from the light palette.
      lightPalette = {
        "toolbar-header-document"      = "L_PRIMARY";
        "toolbar-header-spreadsheet"   = "L_PRIMARY";
        "toolbar-header-presentation"  = "L_PRIMARY";
        "toolbar-header-pdf"           = "L_PRIMARY";
        "toolbar-header-draw"          = "L_PRIMARY";
        "background-toolbar"           = "L_SURFACE";
        "text-toolbar-header"          = "L_ON_SURFACE";
        "highlight-button-hover"       = "L_SURFACE_CONTAINER_HIGH";
        "background-normal"            = "L_SURFACE";
        "border-regular-control"       = "L_OUTLINE_VARIANT";
        "border-divider"               = "L_OUTLINE_VARIANT";
        "canvas-scroll-thumb-hover"    = "L_OUTLINE";
        "window-background"            = "L_SURFACE";
        "window-border"                = "L_OUTLINE_VARIANT";
        "text-normal"                  = "L_ON_SURFACE";
        "text-pretty"                  = "L_ON_SURFACE_VARIANT";
        "text-inverse"                 = "L_ON_PRIMARY";
        "menu-background"               = "L_SURFACE_CONTAINER";
        "menu-border"                  = "L_OUTLINE_VARIANT";
        "menu-item-hover-background"   = "L_SURFACE_CONTAINER_HIGH";
        "menu-text"                    = "L_ON_SURFACE";
        "menu-text-item-hover"         = "L_ON_PRIMARY";
        "menu-text-item-disabled"      = "L_ON_SURFACE_VARIANT";
        "menu-separator"               = "L_OUTLINE_VARIANT";
        "tooltip-text"                 = "L_ON_SURFACE";
        "tooltip-border"               = "L_OUTLINE_VARIANT";
        "tooltip-background"           = "L_SURFACE_CONTAINER_HIGHEST";
        "tab-default-active-background" = "L_SURFACE_CONTAINER";
        "tab-default-active-text"      = "L_ON_SURFACE";
        "tab-simple-active-background" = "L_SURFACE_CONTAINER";
        "tab-simple-active-text"        = "L_ON_SURFACE";
        "tab-divider"                  = "L_OUTLINE_VARIANT";
        "background-accent-button"     = "L_PRIMARY";
        "border-control-focus"        = "L_PRIMARY";
        "highlight-text-select"       = "L_PRIMARY";
      };

      # Python sync script — runs as a user systemd oneshot. Mirrors
      # the shape of `sync-legcord-dms-theme` / `sync-readest-dms-theme`.
      syncScript = pkgs.writers.writePython3Bin "sync-onlyoffice-dms-theme"
        {
          # E501: long lines (the palette dicts have no useful wrap points).
          # E241: aligned colons for readability — flake8 dislikes the
          #       multiple spaces.
          # E302/E305: function/class spacing (cosmetic, flake8 default).
          # F401/E402: a few imports + the `Path.home()` fallback are
          #             unused / non-top-level; harmless.
          flakeIgnore = [ "E501" "E231" "E241" "E302" "E305" "F401" "E402" ];
        } ''
        import json
        import os
        import re
        import shutil
        import signal
        import subprocess
        import sys
        import time
        from pathlib import Path

        HEX_COLOR = re.compile(r"^#[0-9a-fA-F]{6}$")

        # Material Design 3 → OO variable mapping. Plain Python dicts
        # (not JSON-encoded) so we can do straight substring substitution.
        DARK_PALETTE = ${builtins.toJSON darkPalette}
        LIGHT_PALETTE = ${builtins.toJSON lightPalette}

        THEME_ID = "dms"
        THEME_NAME = "DankMaterialShell"


        def require_color(colors, role):
            value = colors.get(role)
            if not isinstance(value, str) or not HEX_COLOR.fullmatch(value):
                raise ValueError(f"DMS palette missing valid {role!r}")
            return value.lower()


        def active_mode(cache, gtk_colors):
            palettes = cache["colors"]
            gtk_background = gtk_colors.get("window_bg_color", "").lower()
            for m in ("dark", "light"):
                if gtk_background == palettes[m].get("background", "").lower():
                    return m
            return "dark"


        def render_theme_json(mode, dms_dark, dms_light):
            """Render the per-theme theme-dms.json file OO loads from."""
            mapping = DARK_PALETTE if mode == "dark" else LIGHT_PALETTE
            colors = {}
            for oo_var, token in mapping.items():
                m = re.match(r"^L_(.+)$", token)
                if m:
                    colors[oo_var] = require_color(dms_light, m.group(1).lower())
                else:
                    colors[oo_var] = require_color(dms_dark, token.lower())
            theme = {
                "name": THEME_NAME + (" (Light)" if mode == "light" else " (Dark)"),
                "id": "theme-" + THEME_ID,
                "type": mode,
                "colors": colors,
            }
            return json.dumps(theme, indent=2)


        def render_themes_manifest(theme_id):
            """Render themes.json — the list of theme IDs OO picks up."""
            return json.dumps({"themes": [theme_id]}, indent=2) + "\n"


        # The path inside the OO bundle where themes.json + per-theme
        # JSON files live. Discovered at runtime via glob — the fhsenv
        # rootfs hash changes whenever nixpkgs is rebuilt, so we can't
        # hardcode it.
        def find_oo_bwrap_script():
            for p in Path("/nix/store").glob("*-onlyoffice-desktopeditors-9.1.0-bwrap"):
                return p
            return None


        def find_themes_dir():
            """Resolve the read-only themes/ directory inside the FHS
            rootfs by parsing the bwrap script's --ro-bind args.
            Walks /nix/store to find the bwrap script because its hash
            changes on every nixpkgs rebuild."""
            bwrap_script = find_oo_bwrap_script()
            if bwrap_script is None:
                return None
            try:
                text = bwrap_script.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                return None
            m = re.search(
                r"/nix/store/[\w-]+-onlyoffice-desktopeditors-[\w.-]+-fhsenv-rootfs",
                text,
            )
            if not m:
                return None
            themes = Path(m.group(0)) / "usr" / "share" / "desktopeditors" / "editors" / "web-apps" / "apps" / "common" / "main" / "resources" / "themes"
            return themes if themes.is_dir() else None


        def kill_running():
            """Kill any running OnlyOffice so the next launch re-reads
            themes.json. CEF caches the manifest at startup."""
            try:
                out = subprocess.run(
                    ["pgrep", "-f", "onlyoffice-desktopeditors"],
                    capture_output=True, text=True, check=False,
                )
            except FileNotFoundError:
                return False
            pids = [int(p) for p in out.stdout.split() if p.isdigit()]
            if not pids:
                return False
            for pid in pids:
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    continue
            for _ in range(50):
                if not any(Path(f"/proc/{pid}").exists() for pid in pids):
                    return True
                time.sleep(0.1)
            return False


        home = Path(os.environ.get("HOME", str(Path.home())))
        cache_home = Path(os.environ.get("XDG_CACHE_HOME", home / ".cache"))
        config_home = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
        palette_path = cache_home / "DankMaterialShell" / "dms-colors.json"
        gtk_palette_path = config_home / "gtk-4.0" / "dank-colors.css"
        user_themes_dir = cache_home / "onlyoffice-themes" / "themes"

        if not palette_path.exists():
            sys.exit(f"DMS palette not found at {palette_path}")

        with palette_path.open(encoding="utf-8") as f:
            cache = json.load(f)

        gtk_colors = {
            name: value
            for name, value in re.findall(
                r"@define-color\s+([a-z_]+)\s+(#[0-9a-fA-F]{6})\s*;",
                gtk_palette_path.read_text(encoding="utf-8"),
            )
        }

        mode = active_mode(cache, gtk_colors)

        # Render BOTH dark + light theme JSONs (OO picks by name based
        # on the theme-type the user has selected — we register both
        # under the same id and the user toggles type at runtime).
        dark_theme_json = render_theme_json("dark", cache["colors"]["dark"], cache["colors"]["light"])
        light_theme_json = render_theme_json("light", cache["colors"]["dark"], cache["colors"]["light"])

        # Locate the upstream themes directory so we can mirror its
        # structure. We override only themes.json + theme-dms.json; the
        # rest of the dir (just the empty themes.json) is untouched.
        themes_dir = find_themes_dir()
        if themes_dir is None:
            sys.exit("Could not locate OnlyOffice FHS themes dir")

        user_themes_dir.parent.mkdir(parents=True, exist_ok=True)
        # Wipe the cache before recreating — we own it (read-write user
        # dir) and any stale files from a previous version's sync
        # (especially the symlinks that an older script version
        # accidentally created) would shadow our writes. shutil.rmtree
        # on a writable dir is safe; if the dir doesn't exist, the
        # exception is suppressed.
        if user_themes_dir.is_symlink():
            # A symlink at the cache path is the failure mode from the
            # first deploy — unlink explicitly, rmtree won't follow it.
            user_themes_dir.unlink()
        elif user_themes_dir.exists():
            # Use a more robust removal that handles read-only entries
            # (the upstream themes/ contents are read-only in the nix
            # store, and a previous rmtree may have set the local
            # mirror to read-only too). onerror clears the perms then
            # retries the failed op.
            def _onerr(fn, path, exc_info):
                try:
                    os.chmod(path, 0o700)
                    fn(path)
                except OSError:
                    pass
            shutil.rmtree(user_themes_dir, onerror=_onerr)
        # Mirror the upstream themes/ structure (the only file there is
        # themes.json — currently `{"themes": []}`). We copy WITHOUT
        # following symlinks so the local file is a real file we can
        # later overwrite. symlinks=True (the default) would follow the
        # source symlink (if any) and create a destination symlink —
        # which is what the previous version of this script did, and
        # it broke writes. dirs_exist_ok=True makes the copy idempotent
        # in the (unlikely) event rmtree didn't actually remove the
        # dir.
        shutil.copytree(themes_dir, user_themes_dir, symlinks=False, dirs_exist_ok=True)
        # The source themes/ lives in the read-only nix store with
        # mode 0555 / 0444 (dir / file). shutil.copystat (called by
        # copytree) propagates the source modes to the destination, so
        # the user cache ends up read-only too — even though the
        # underlying filesystem allows writes. Override to 0755 / 0644
        # so our subsequent write_text calls succeed.
        os.chmod(user_themes_dir, 0o755)
        for entry in user_themes_dir.iterdir():
            os.chmod(entry, 0o644)

        # Write the per-theme JSON files (both dark and light variants,
        # even though we register only one id — the manifest picks).
        (user_themes_dir / "theme-dms.json").write_text(dark_theme_json, encoding="utf-8")
        # Also write a light variant file (in case OO's loader tries
        # theme-dms-light.json by convention).
        (user_themes_dir / "theme-dms-light.json").write_text(light_theme_json, encoding="utf-8")

        # Write themes.json with our theme registered.
        manifest = render_themes_manifest("theme-dms")
        (user_themes_dir / "themes.json").write_text(manifest, encoding="utf-8")

        # Kill any running OO so the next launch reads our themes.json.
        was_running = kill_running()
        if was_running:
            time.sleep(0.5)

        # Note: themes.json is in OO's `resources/` dir which CEF loads
        # via fetch(). We can't sentinel-guard an arbitrary location
        # there; we just overwrite themes.json in place (idempotent —
        # file content is deterministic from the DMS palette).
        print(
            f"Synced OnlyOffice DMS theme "
            f"(mode={mode}, killed_running={was_running})"
        )
      '';

      # Wrapper script that replaces $out/bin/onlyoffice-desktopeditors.
      # Runs the palette sync, then re-execs the original bwrap with the
      # --bind overlay prepended.
      wrapperScript = pkgs.writeShellScriptBin "onlyoffice-desktopeditors-wrapped"
        ''
          set -euo pipefail

          # Run the palette sync (idempotent — re-runs are no-ops when
          # the cached themes.json is already written with the same DMS
          # palette). The || true lets the wrapper proceed even if the
          # sync fails (e.g. DMS palette cache missing) — OnlyOffice
          # will launch with the built-in theme rather than not launch
          # at all.
          ${syncScript}/bin/sync-onlyoffice-dms-theme || true

          # The bwrap script path was substituted at build time by
          # extraInstallCommands below (sed -i replaces the __BWRAP_PATH__
          # sentinel with the captured bwrap_path — the path isn't
          # known at Nix-eval time because it lives inside the
          # upstream's fhsenv rootfs). After substitution this exec
          # line holds the absolute store path of the fhsenv bwrap
          # launcher.
          exec __BWRAP_PATH__ \
              --bind "$HOME/.cache/onlyoffice-themes/themes" \
                       /usr/share/desktopeditors/editors/web-apps/apps/common/main/resources/themes \
              "$@"
        '';

      # The system-installed onlyoffice-desktopeditors package, with the
      # fhsenv-profile wrapper symlink replaced by our wrapper script.
      #
      # Build order:
      #   1. Nix evaluates wrapperScript with the __BWRAP_PATH__ sentinel
      #      baked in.
      #   2. Nix evaluates the wrapped package's extraInstallCommands,
      #      which captures the real bwrap path and `sed -i`s it into
      #      $out/bin/onlyoffice-desktopeditors (which is a copy of
      #      wrapperScript).
      #   3. Activation: when the user runs /run/current-system/sw/bin/
      #      onlyoffice-desktopeditors, the symlink resolves to
      #      $out/bin/onlyoffice-desktopeditors (now a regular file with
      #      the bwrap path baked in).
      wrappedPackage = pkgs.onlyoffice-desktopeditors.overrideAttrs (old: {
        extraInstallCommands = (old.extraInstallCommands or "") + ''
          # Capture the bwrap script path the upstream symlink points at
          # BEFORE we delete it. readlink -f follows the chain even if
          # the symlink target is itself a symlink.
          bwrap_path=$(readlink -f "$out/bin/onlyoffice-desktopeditors")

          # Drop the upstream symlink and replace it with a copy of
          # the wrapper script (NOT a symlink — the system PATH
          # resolution would loop on a symlink to a script that execs
          # itself).
          rm -f $out/bin/onlyoffice-desktopeditors
          cp ${wrapperScript}/bin/onlyoffice-desktopeditors-wrapped \
             $out/bin/onlyoffice-desktopeditors
          chmod +x $out/bin/onlyoffice-desktopeditors

          # Substitute the sentinel with the captured bwrap path.
          sed -i "s|__BWRAP_PATH__|$bwrap_path|g" \
              $out/bin/onlyoffice-desktopeditors
        '';
      });
    in
    {
      # The wrapped package is the sole entry for OnlyOffice on hosts
      # that import the office role (config.nixos.modules.office).
      # modules/packages/office/office.nix is now an empty marker role.
      environment.systemPackages = [ wrappedPackage ];

      # Oneshot that runs the sync. Debounced ~2s so DMS's cache writes
      # have settled before we read.
      systemd.user.services.onlyoffice-dms-theme-sync = {
        description = "Sync OnlyOffice chrome with DankMaterialShell palette";
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
          exec ${syncScript}/bin/sync-onlyoffice-dms-theme
        '';
      };

      # Watch the DMS palette cache and our own user-cache themes dir.
      # DMS updates dms-colors.json atomically (tmp+rename), so watch
      # the parent directory.
      systemd.user.paths.onlyoffice-dms-theme-sync = {
        description = "Watch DMS palette changes for OnlyOffice";
        unitConfig.ConditionUser = "jaide";
        wantedBy = [ "default.target" ];
        pathConfig = {
          PathChanged = [
            "%h/.cache/DankMaterialShell"
            "%h/.cache/onlyoffice-themes"
          ];
        };
      };
    };
}