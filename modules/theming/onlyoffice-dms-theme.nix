# OnlyOffice desktop custom theme — ships a sample `theme-dms.json` /
# `theme-dms-light.json` and an installer that drops them into the right
# per-user directory that the C++ `DesktopEditors` binary actually reads
# from at startup.
#
# ## How OO loads custom themes (verified from source)
#
# The C++ side reads the `UITheme` value from
# `~/.config/onlyoffice/DesktopEditors.conf` (a QSettings value), then
# looks for a file with a matching name in a `uithemes/` directory. The
# code is in `win-linux/src/cthemes.cpp` (desktop-apps repo):
#
#   void CThemesPrivate::searchLocalThemes() {
#       QFileInfoList themes = QDir(qApp->applicationDirPath() + "/uithemes")
#           .entryInfoList(... << "*.json", QDir::Files);
#       themes.append(QDir(Utils::getAppCommonPath() + "/uithemes")
#           .entryInfoList(... << "*.json", QDir::Files));
#       foreach (auto t, themes) { addThemeFromFile(t.absoluteFilePath()); }
#   }
#
# Where `Utils::getAppCommonPath()` returns
# `QStandardPaths::GenericDataLocation + APP_DATA_PATH` and
# `APP_DATA_PATH = "/onlyoffice/desktopeditors"`. On Linux that's
# `~/.local/share/onlyoffice/desktopeditors/`.
#
# So the user-writable location is:
#   ~/.local/share/onlyoffice/desktopeditors/uithemes/*.json
#
# Each file must:
#   - be a JSON object with at minimum `id` and `name` (string).
#   - have a `colors` map with keys matching the `s` array in
#     `editors/web-apps/apps/common/main/lib/controller/Themes.js`.
#   - the `id` regex is `[\\w\\d\\-]+` — alphanumeric + dash only.
#
# The JS-side theme registry (Settings → Interface theme) is populated
# from the C++ side via `Common.Controllers.Desktop.localThemes()`,
# which returns the parsed array of every JSON in `uithemes/`. So the
# file-based mechanism is the only path — the `localthemes` QSettings
# key is **not** what the C++ side reads (we tried that first and the
# validator rejected the format).
#
# ## Apply mechanism
#
#   - C++ reads `UITheme` and the matching file at startup, registers
#     the theme in its in-memory list.
#   - When the user picks a theme from Settings → Interface theme, the
#     JS theme registry rebuilds the stylesheet via
#     `apply_icons_from_url()` and the theme CSS is injected. Apply is
#     LIVE for the currently running OO.
#   - Editing the JSON file on disk has NO effect until OO is
#     restarted (or the user re-picks the theme from the menu, which
#     re-reads the file via `fromFile`).
#
# What this module does NOT do (intentionally — kept minimal so we can
# observe the apply mechanism before automating it):
#   - No DMS palette sync (no watcher, no python script)
#   - No bind mount of the fhsenv's themes/ dir
#   - No automatic kill of running OO on theme change
_:
{
  nixos.modules.common =
    { pkgs, lib, ... }:

    let
      # The sample dark theme. The `colors` dict uses Material Design 3
      # tokens mapped to a sober dark palette inspired by DankMaterialShell
      # (the "maguten" palette the user is running). Edit these colors
      # and re-pick the theme in OO to see the apply mechanism in action.
      #
      # The full set of valid keys is the `s` array in
      # `editors/web-apps/apps/common/main/lib/controller/Themes.js`
      # (~80+ CSS variables). The subset below is what controls the
      # visible chrome — toolbar, header, sidebar, menus, scrollbars,
      # buttons.
      themeDmsDark = {
        id = "theme-dms";
        name = "DankMaterialShell";
        type = "dark";
        colors = {
          "toolbar-header-document"      = "#7c4dff";
          "toolbar-header-spreadsheet"   = "#7c4dff";
          "toolbar-header-presentation"  = "#7c4dff";
          "toolbar-header-pdf"           = "#7c4dff";
          "toolbar-header-visio"         = "#7c4dff";
          "text-toolbar-header"          = "#ffffff";
          "background-toolbar"           = "#1c1b1f";
          "background-normal"            = "#141318";
          "window-background"            = "#141318";
          "text-normal"                  = "#e6e1e5";
          "text-secondary"               = "#cac4d0";
          "border-divider"               = "#3a3640";
          "border-regular-control"       = "#49454f";
          "background-accent-button"     = "#7c4dff";
          "highlight-button-hover"       = "#2a2730";
          "highlight-text-select"        = "#7c4dff";
          "canvas-background"            = "#1c1b1f";
          "canvas-content-background"    = "#1c1b1f";
        };
      };

      # The same theme, but in a "light" type for users who pick light mode.
      themeDmsLight = {
        id = "theme-dms";
        name = "DankMaterialShell";
        type = "light";
        colors = {
          "toolbar-header-document"      = "#6750a4";
          "toolbar-header-spreadsheet"   = "#6750a4";
          "toolbar-header-presentation"  = "#6750a4";
          "toolbar-header-pdf"           = "#6750a4";
          "toolbar-header-visio"         = "#6750a4";
          "text-toolbar-header"          = "#ffffff";
          "background-toolbar"           = "#f4eff7";
          "background-normal"            = "#fef7ff";
          "window-background"            = "#fef7ff";
          "text-normal"                  = "#1d1b20";
          "text-secondary"               = "#49454f";
          "border-divider"               = "#cac4d0";
          "border-regular-control"       = "#79747e";
          "background-accent-button"     = "#6750a4";
          "highlight-button-hover"       = "#e7e0ec";
          "highlight-text-select"        = "#6750a4";
          "canvas-background"            = "#fef7ff";
          "canvas-content-background"    = "#fef7ff";
        };
      };

      themeDmsJson = builtins.toJSON themeDmsDark;
      themeDmsLightJson = builtins.toJSON themeDmsLight;

      # Helper script: drop the theme JSON files into the user's
      # `~/.local/share/onlyoffice/desktopeditors/uithemes/` dir and set
      # `UITheme=theme-dms` in their `DesktopEditors.conf`. Idempotent —
      # re-running just refreshes the files.
      installScript = pkgs.writeShellScriptBin "install-onlyoffice-dms-theme" ''
        set -euo pipefail

        target_user="''${1:-}"
        if [ -z "$target_user" ]; then
          target_user="$(id -un)"
        fi

        # Resolve $HOME for the target user via getent, falling back to
        # /etc/passwd awk if getent isn't available.
        if command -v getent >/dev/null 2>&1; then
          home="$(getent passwd "$target_user" | cut -d: -f6)"
        else
          home="$(awk -F: -v u="$target_user" '$1==u {print $6}' /etc/passwd)"
        fi
        if [ -z "$home" ]; then
          echo "install-onlyoffice-dms-theme: cannot resolve HOME for user '$target_user'" >&2
          exit 1
        fi

        themes_dir="$home/.local/share/onlyoffice/desktopeditors/uithemes"
        conf_file="$home/.config/onlyoffice/DesktopEditors.conf"

        # Ensure the uithemes dir exists and is owned by the target user.
        mkdir -p "$themes_dir"
        chown "$target_user:$(id -gn "$target_user" 2>/dev/null || echo "$target_user")" "$themes_dir"

        # Write the theme files. The C++ side reads these at startup
        # (see cthemes.cpp: CThemesPrivate::searchLocalThemes). The
        # `id` field MUST contain only [\w\d\-] characters or
        # validateTheme() rejects the file.
        cat > "$themes_dir/theme-dms.json" <<'THEME_DARK_EOF'
        ${themeDmsJson}
        THEME_DARK_EOF
        cat > "$themes_dir/theme-dms-light.json" <<'THEME_LIGHT_EOF'
        ${themeDmsLightJson}
        THEME_LIGHT_EOF
        chown -R "$target_user:$(id -gn "$target_user" 2>/dev/null || echo "$target_user")" "$themes_dir"
        chmod 0644 "$themes_dir"/theme-dms*.json

        # Ensure conf dir exists, then set UITheme=theme-dms in
        # DesktopEditors.conf while preserving other keys/ordering.
        mkdir -p "$(dirname "$conf_file")"
        if [ ! -f "$conf_file" ]; then
          cat > "$conf_file" <<'EOFCONF'
        [General]
        EOFCONF
        fi

        # Inject / update UITheme in the [General] section without
        # touching other keys. Use a small Python helper because
        # configparser lowercases keys and reorders sections — we want
        # to preserve the user's other settings exactly.
        python3 - "$conf_file" "$target_user" <<'PYEOF'
        import os
        import sys

        conf_file, target_user = sys.argv[1], sys.argv[2]

        with open(conf_file) as f:
            raw = f.read()

        lines = raw.splitlines(keepends=False)
        out = []
        in_general = False
        inserted = False
        for ln in lines:
            stripped = ln.lstrip()
            if stripped.startswith("["):
                in_general = stripped == "[General]"
                out.append(ln)
                continue
            if in_general and "=" in ln:
                key = ln.split("=", 1)[0].strip()
                if key == "UITheme":
                    out.append("UITheme=theme-dms")
                    inserted = True
                    continue
            out.append(ln)

        if not any(ln.strip() == "[General]" for ln in out):
            out.append("[General]")
            in_general = True

        if in_general and not inserted:
            out.append("UITheme=theme-dms")

        with open(conf_file, "w") as f:
            f.write("\n".join(out) + "\n")

        try:
            import grp
            gid = grp.getgrnam(target_user).gr_gid
        except (KeyError, ImportError):
            gid = -1
        os.chown(conf_file, -1, gid)
        PYEOF

        echo "Installed 'theme-dms' for user '$target_user'."
        echo "  Wrote: $themes_dir/theme-dms.json"
        echo "  Wrote: $themes_dir/theme-dms-light.json"
        echo "  Set:   UITheme=theme-dms in $conf_file"
        echo ""
        echo "Restart OnlyOffice and pick 'DankMaterialShell' from"
        echo "  Settings → Interface theme to apply."
      '';

      # Pure-passthrough wrapper. Just `exec` the original bwrap script.
      wrapperScript = pkgs.writeShellScriptBin "onlyoffice-desktopeditors-wrapped"
        ''
          # bwrap inherits the calling process's CWD and chdirs into
          # it inside the namespace. If the invoker ran from a
          # directory the user can't enter (e.g. a different user's
          # $HOME), bwrap fails with "Can't chdir to ...". cd to /tmp
          # first so we always have a safe, accessible CWD. The user
          # can still pass a file path as an argument and OO will
          # open it; we don't depend on CWD for that.
          cd /tmp
          exec __BWRAP_PATH__ "$@"
        '';

      # The system-installed onlyoffice-desktopeditors package, with
      # the fhsenv-profile wrapper symlink replaced by our wrapper
      # script. Build order:
      #   1. Nix evaluates wrapperScript with the __BWRAP_PATH__
      #      sentinel baked in.
      #   2. Nix evaluates the wrapped package's extraInstallCommands,
      #      which captures the real bwrap path and `sed -i`s it into
      #      $out/bin/onlyoffice-desktopeditors (a copy of
      #      wrapperScript).
      #   3. Activation: /run/current-system/sw/bin/onlyoffice-desktopeditors
      #      is a symlink to $out/bin/onlyoffice-desktopeditors (now a
      #      regular file with the bwrap path baked in).
      #
      # The package's resources/themes/ dir is left alone — OO doesn't
      # read custom themes from there (the C++ side reads
      # ~/.local/share/onlyoffice/desktopeditors/uithemes/*.json
      # instead). The sample files in resources/ are kept for
      # reference / inspection only.
      wrappedPackage = pkgs.onlyoffice-desktopeditors.overrideAttrs (old: {
        extraInstallCommands = (old.extraInstallCommands or "") + ''
          bwrap_path=$(readlink -f "$out/bin/onlyoffice-desktopeditors")
          rm -f $out/bin/onlyoffice-desktopeditors
          cp ${wrapperScript}/bin/onlyoffice-desktopeditors-wrapped \
             $out/bin/onlyoffice-desktopeditors
          chmod +x $out/bin/onlyoffice-desktopeditors
          sed -i "s|__BWRAP_PATH__|$bwrap_path|g" \
              $out/bin/onlyoffice-desktopeditors
        '';
      });
    in
    {
      # The wrapped package is the sole entry for OnlyOffice on hosts
      # that import the office role (config.nixos.modules.office).
      environment.systemPackages = [
        wrappedPackage
        installScript
      ];
    };
}
