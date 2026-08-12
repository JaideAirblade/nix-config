# OnlyOffice desktop custom theme — minimal: ships a sample `theme-dms.json`
# inside the package's resources/themes/ directory and provides a small
# helper script the user can run to register it as a custom theme in
# OnlyOffice's `DesktopEditors.conf` `localthemes` key. The user then
# picks "DankMaterialShell" from Settings → Interface theme.
#
# Why a custom JSON via `localthemes` and not "drop a file in resources/":
# OnlyOffice's C++ binary hardcodes the list of built-in theme files
# (theme-classic-light.json, theme-night.json, ... — see `strings` of
# `share/desktopeditors/DesktopEditors`). Dropping a new file in the
# resources dir doesn't register it. The only way to add a custom theme
# that's selectable in the UI is the `localthemes` QSettings key, which
# holds a JSON blob of `{themes: [{id, name, type, colors: {...}}, ...]}`.
# The C++ side parses that and exposes the entries via
# `Common.Controllers.Desktop.localThemes()` to the JS theme registry.
#
# What this module does NOT do (intentionally — kept minimal so we can
# observe the apply mechanism before automating it):
#   - No DMS palette sync (no watcher, no python script)
#   - No bind mount of the fhsenv's themes/ dir
#   - No automatic kill of running OO on theme change
#
# Apply mechanism (observed by reading the OO JS in
# `editors/web-apps/apps/common/main/lib/controller/Themes.js`):
#   - The JS theme registry is populated once at startup from
#     `Common.Controllers.Desktop.localThemes()`. CEF/Desktop reads the
#     `localthemes` QSettings value at that point.
#   - The `colors` dict in each entry is applied as CSS custom
#     properties (`--<key>: <value>`) on `:root .<theme-id> { ... }`.
#     The stylesheet is created at the time the user picks the theme
#     from the menu.
#   - CEF does NOT watch the QSettings file. Editing `localthemes` after
#     OO is running has NO effect until OO restarts.
#   - Switching themes in the OO menu (Settings → Interface theme) is
#     LIVE — the new CSS is injected immediately without restart.
#
# So:
#   - To test a color change: edit the JSON in `localthemes`, then go
#     to Settings → Interface theme and re-select the theme. Or restart
#     OO.
#   - The user asked specifically to verify this — so we ship the theme
#     and a way to install it, and let them try both.
_:
{
  nixos.modules.common =
    { pkgs, lib, ... }:

    let
      # The sample theme. The `colors` dict uses Material Design 3
      # tokens mapped to a sober dark palette inspired by DankMaterialShell
      # (the "maguten" palette the user is running). Edit these colors
      # and re-pick the theme in OO to see the apply mechanism in action.
      #
      # The full set of valid keys is the `s` array in
      # `editors/web-apps/apps/common/main/lib/controller/Themes.js`
      # (~80+ CSS variables). The subset below is what controls the
      # visible chrome — toolbar, header, sidebar, menus, scrollbars,
      # buttons. The full set can be added later if a color doesn't
      # render as expected.
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

      # The localthemes JSON blob that gets put into DesktopEditors.conf.
      localthemesBlob = builtins.toJSON {
        themes = [ themeDmsDark themeDmsLight ];
      };

      # The sample theme files dropped into the package resources dir, so
      # the user can inspect them and copy/adapt the format.
      themeDmsJson = builtins.toJSON themeDmsDark;
      themeDmsLightJson = builtins.toJSON themeDmsLight;
      themesManifest = builtins.toJSON {
        themes = [ "theme-dms" ];
      };

      # Helper script: install the theme into the user's
      # `~/.config/onlyoffice/DesktopEditors.conf` so it appears in
      # Settings → Interface theme. Idempotent — re-running just
      # updates the existing entry.
      #
      # Usage:
      #   install-onlyoffice-dms-theme              # install for current user
      #   install-onlyoffice-dms-theme --user jaide # install for a specific user
      installScript = pkgs.writeShellScriptBin "install-onlyoffice-dms-theme" ''
        set -euo pipefail

        target_user="''${1:-}"
        if [ -n "$target_user" ] && [ "''${2:-}" = "--user" ]; then
          target_user="$2"
        fi
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

        conf_dir="$home/.config/onlyoffice"
        conf_file="$conf_dir/DesktopEditors.conf"

        # Ensure config dir exists and is owned by the target user.
        if [ ! -d "$conf_dir" ]; then
          mkdir -p "$conf_dir"
          chown "$target_user:$(id -gn "$target_user" 2>/dev/null || echo "$target_user")" "$conf_dir"
        fi

        # If the conf doesn't exist, write a minimal one.
        if [ ! -f "$conf_file" ]; then
          cat > "$conf_file" <<'EOFCONF'
        [General]
        EOFCONF
          chown "$target_user:$(id -gn "$target_user" 2>/dev/null || echo "$target_user")" "$conf_file"
        fi

        # Inject the localthemes key and UITheme while preserving
        # existing keys/ordering. Use a small Python helper because
        # configparser lowercases keys and reorders sections — we want
        # the file to stay exactly as the user left it otherwise.
        blob='${localthemesBlob}'

        python3 - "$conf_file" "$target_user" "$blob" <<'PYEOF'
        import os
        import sys

        conf_file, target_user, blob = sys.argv[1], sys.argv[2], sys.argv[3]

        with open(conf_file) as f:
            raw = f.read()

        lines = raw.splitlines(keepends=False)
        out = []
        in_general = False
        inserted = {"localthemes": False, "UITheme": False}
        for ln in lines:
            stripped = ln.lstrip()
            if stripped.startswith("["):
                in_general = stripped == "[General]"
                out.append(ln)
                continue
            if in_general and "=" in ln:
                key = ln.split("=", 1)[0].strip()
                if key in inserted:
                    if key == "localthemes":
                        out.append(f"localthemes={blob}")
                    elif key == "UITheme":
                        out.append("UITheme=theme-dms")
                    inserted[key] = True
                    continue
            out.append(ln)

        if not any(ln.strip() == "[General]" for ln in out):
            out.append("[General]")
            in_general = True

        if in_general:
            for key, val in (("localthemes", blob), ("UITheme", "theme-dms")):
                if not inserted[key]:
                    out.append(f"{key}={val}")

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
        echo "Restart OnlyOffice and pick 'DankMaterialShell' from"
        echo "  Settings → Interface theme to apply."
      '';

      # Pure-passthrough wrapper. Just `exec` the original bwrap script.
      # No sync, no bind mount, no kill, no extra args. The user can
      # launch OO without any of the previous theming shenanigans.
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
      wrappedPackage = pkgs.onlyoffice-desktopeditors.overrideAttrs (old: {
        extraInstallCommands = (old.extraInstallCommands or "") + ''
          bwrap_path=$(readlink -f "$out/bin/onlyoffice-desktopeditors")
          rm -f $out/bin/onlyoffice-desktopeditors
          cp ${wrapperScript}/bin/onlyoffice-desktopeditors-wrapped \
             $out/bin/onlyoffice-desktopeditors
          chmod +x $out/bin/onlyoffice-desktopeditors
          sed -i "s|__BWRAP_PATH__|$bwrap_path|g" \
              $out/bin/onlyoffice-desktopeditors

          # Drop the sample theme files into the package's resources/
          # themes/ dir. The C++ side doesn't auto-register themes from
          # the manifest in this dir (built-in themes are hardcoded),
          # but having the files there is useful for:
          #   1. Reference: the user can read the format and adapt
          #      the colors.
          #   2. Future work: a fhsenv-rootfs override could expose
          #      them at /usr/share/.../themes/ as proper built-ins.
          themes_dir="$out/share/desktopeditors/editors/web-apps/apps/common/main/resources/themes"
          mkdir -p "$themes_dir"
          cat > "$themes_dir/theme-dms.json" <<'THEME_DARK_EOF'
        ${themeDmsJson}
        THEME_DARK_EOF
          cat > "$themes_dir/theme-dms-light.json" <<'THEME_LIGHT_EOF'
        ${themeDmsLightJson}
        THEME_LIGHT_EOF
          cat > "$themes_dir/themes.json" <<'MANIFEST_EOF'
        ${themesManifest}
        MANIFEST_EOF
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
