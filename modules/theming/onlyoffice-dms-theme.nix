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
      # Material Design 3 dark scheme. `values` is the C++ theme
      # schema (read at win-linux/src/cthemes.cpp:329 —
      # "jsonValues = obj.value(\"values\").toObject()"). The key set
      # is the same as upstream's theme-night.json (the default
      # built-in dark), with M3-mapped DMS color values swapped in.
      # Special keys (button-normal-opacity, logo-type) keep their
      # upstream values — they're not theme colors.
      themeDmsDark = {
        id = "theme-dms";
        name = "DankMaterialShell";
        type = "dark";
        values = {
          "border-control-focus"                        = "#7c4dff";
          "brand-cell"                                  = "#7c4dff";
          "brand-draw"                                  = "#7c4dff";
          "brand-pdf"                                   = "#7c4dff";
          "brand-slide"                                 = "#7c4dff";
          "brand-word"                                  = "#7c4dff";
          "button-normal-opacity"                       = "rgba(255,255,255,200)";
          "download-ghost-button-text"                  = "#a08cff";
          "download-ghost-button-text-hover"            = "#e6e1e5";
          "download-ghost-button-text-pressed"          = "#cac4d0";
          "download-ghost-button-text-pressed-item-hover" = "#cac4d0";
          "download-item-hover-background"             = "#2a2930";
          "download-label-text"                         = "#e6e1e5";
          "download-label-text-info"                    = "#cac4d0";
          "download-label-text-info-item-hover"         = "#cac4d0";
          "download-progressbar-background"             = "#49454f";
          "download-progressbar-background-item-hover"  = "#49454f";
          "download-progressbar-chunk"                  = "#7c4dff";
          "download-scrollbar-handle"                   = "#948f99";
          "download-widget-background"                 = "#201f23";
          "download-widget-border"                      = "#49454f";
          "logo-type"                                   = "dark";
          "menu-background"                             = "#201f23";
          "menu-border"                                 = "#49454f";
          "menu-item-hover-background"                  = "#2a2930";
          "menu-separator"                              = "#49454f";
          "menu-text"                                   = "#e6e1e5";
          "menu-text-item-disabled"                     = "#cac4d0";
          "menu-text-item-hover"                        = "#ffffff";
          "tab-active-background"                       = "#141318";
          "tab-default-active-background"               = "#141318";
          "tab-default-active-text"                     = "#e6e1e5";
          "tab-divider"                                 = "#49454f";
          "tab-simple-active-background"                = "#141318";
          "tab-simple-active-text"                      = "#e6e1e5";
          "text-inverse"                                = "#7c4dff";
          "text-normal"                                 = "#e6e1e5";
          "text-pretty"                                 = "#e6e1e5";
          "tool-button-active-background"               = "#7c4dff";
          "tool-button-background"                      = "#1c1b1f";
          "tool-button-hover-background"                = "#201f23";
          "tool-button-pressed-background"              = "#2a2930";
          "tooltip-background"                          = "#35343a";
          "tooltip-border"                              = "#49454f";
          "tooltip-text"                                = "#e6e1e5";
          "window-background"                           = "#141318";
          "window-border"                               = "#49454f";
        };
        # `colors` is the JS theme schema (read at
        # editors/web-apps/.../Themes.js — `t.src.colors` is applied as
        # CSS custom properties). 116 keys, all of the s[] array
        # from the OO web-apps theme controller. Mapped from M3 dark.
        colors = {
          "background-accent-button"               = "#7c4dff";
          "background-contrast-popover"            = "#35343a";
          "background-loader"                      = "#201f23";
          "background-normal"                      = "#141318";
          "background-notification-badge"          = "#f2b8b5";
          "background-notification-popover"        = "#35343a";
          "background-primary-dialog-button"       = "#7c4dff";
          "background-scrim"                       = "#000000";
          "background-toolbar"                     = "#1c1b1f";
          "background-toolbar-additional"          = "#201f23";
          "border-color-shading"                   = "#49454f";
          "border-contrast-popover"                = "#948f99";
          "border-control-focus"                   = "#7c4dff";
          "border-divider"                         = "#49454f";
          "border-error"                           = "#f2b8b5";
          "border-preview-hover"                   = "#7c4dff";
          "border-preview-select"                  = "#7c4dff";
          "border-regular-control"                 = "#49454f";
          "border-toolbar"                         = "#49454f";
          "border-toolbar-button-hover"            = "#948f99";
          "canvas-anim-pane-background"            = "#35343a";
          "canvas-background"                      = "#36343b";
          "canvas-cell-border"                     = "#49454f";
          "canvas-cell-title-background"           = "#201f23";
          "canvas-cell-title-background-hover"     = "#2a2930";
          "canvas-cell-title-background-selected"   = "#4f378b";
          "canvas-cell-title-border"               = "#49454f";
          "canvas-cell-title-border-hover"         = "#948f99";
          "canvas-cell-title-border-selected"      = "#7c4dff";
          "canvas-cell-title-text"                 = "#e6e1e5";
          "canvas-content-background"              = "#36343b";
          "canvas-dark-cell-title"                 = "#141318";
          "canvas-dark-cell-title-border"          = "#49454f";
          "canvas-dark-cell-title-border-hover"    = "#948f99";
          "canvas-dark-cell-title-border-selected" = "#7c4dff";
          "canvas-dark-cell-title-hover"           = "#141318";
          "canvas-dark-cell-title-selected"        = "#7c4dff";
          "canvas-dark-content-background"         = "#141318";
          "canvas-dark-page-border"                = "#49454f";
          "canvas-freeze-line-1px"                 = "#948f99";
          "canvas-freeze-line-2px"                 = "#7c4dff";
          "canvas-high-contrast"                   = "#e6e1e5";
          "canvas-high-contrast-disabled"          = "#cac4d0";
          "canvas-page-border"                     = "#49454f";
          "canvas-ruler-background"                = "#1c1b1f";
          "canvas-ruler-border"                    = "#49454f";
          "canvas-ruler-handle-border"             = "#948f99";
          "canvas-ruler-handle-border-disabled"    = "#49454f";
          "canvas-ruler-margins-background"        = "#201f23";
          "canvas-ruler-mark"                      = "#cac4d0";
          "canvas-scroll-arrow"                    = "#cac4d0";
          "canvas-scroll-arrow-hover"              = "#e6e1e5";
          "canvas-scroll-arrow-pressed"            = "#e6e1e5";
          "canvas-scroll-thumb"                    = "#49454f";
          "canvas-scroll-thumb-border"             = "#141318";
          "canvas-scroll-thumb-border-hover"       = "#141318";
          "canvas-scroll-thumb-border-pressed"     = "#141318";
          "canvas-scroll-thumb-hover"              = "#948f99";
          "canvas-scroll-thumb-pressed"            = "#cac4d0";
          "canvas-scroll-thumb-target"             = "#7c4dff";
          "canvas-scroll-thumb-target-hover"       = "#7c4dff";
          "canvas-scroll-thumb-target-pressed"     = "#7c4dff";
          "canvas-select-all-icon"                 = "#e6e1e5";
          "canvas-sheet-view-cell-background"      = "#201f23";
          "canvas-sheet-view-cell-background-hover"= "#2a2930";
          "canvas-sheet-view-cell-background-pressed" = "#35343a";
          "canvas-sheet-view-cell-title-label"     = "#e6e1e5";
          "highlight-accent-button-hover"          = "#eaddff";
          "highlight-accent-button-pressed"        = "#4f378b";
          "highlight-button-hover"                 = "#2a2930";
          "highlight-button-pressed"               = "#35343a";
          "highlight-button-pressed-hover"         = "#35343a";
          "highlight-header-button-hover"          = "#2a2930";
          "highlight-header-button-pressed"        = "#35343a";
          "highlight-header-tab-underline-document"    = "#7c4dff";
          "highlight-header-tab-underline-pdf"         = "#7c4dff";
          "highlight-header-tab-underline-presentation"= "#7c4dff";
          "highlight-header-tab-underline-spreadsheet" = "#7c4dff";
          "highlight-header-tab-underline-visio"       = "#7c4dff";
          "highlight-primary-dialog-button-hover"  = "#eaddff";
          "highlight-text-select"                  = "#4f378b";
          "highlight-toolbar-tab-underline-document"    = "#7c4dff";
          "highlight-toolbar-tab-underline-pdf"         = "#7c4dff";
          "highlight-toolbar-tab-underline-presentation"= "#7c4dff";
          "highlight-toolbar-tab-underline-spreadsheet" = "#7c4dff";
          "highlight-toolbar-tab-underline-visio"       = "#7c4dff";
          "icon-contrast-popover"                   = "#e6e1e5";
          "icon-inverse"                           = "#322f35";
          "icon-normal"                            = "#e6e1e5";
          "icon-normal-pressed"                    = "#cac4d0";
          "icon-notification-badge"                = "#601410";
          "icon-success"                           = "#efb8c8";
          "icon-toolbar-header"                    = "#ffffff";
          "shadow-contrast-popover"                = "#000000";
          "text-alt-key-hint"                      = "#cac4d0";
          "text-contrast-background"               = "#e6e1e5";
          "text-inverse"                           = "#e6e1e5";
          "text-link"                              = "#7c4dff";
          "text-link-active"                       = "#7c4dff";
          "text-link-hover"                        = "#7c4dff";
          "text-link-visited"                      = "#7c4dff";
          "text-normal"                            = "#e6e1e5";
          "text-normal-pressed"                    = "#e6e1e5";
          "text-secondary"                         = "#cac4d0";
          "text-tertiary"                          = "#cac4d0";
          "text-toolbar-header"                    = "#ffffff";
          "text-toolbar-header-on-background-document"    = "#ffffff";
          "text-toolbar-header-on-background-pdf"         = "#ffffff";
          "text-toolbar-header-on-background-presentation"= "#ffffff";
          "text-toolbar-header-on-background-spreadsheet" = "#ffffff";
          "text-toolbar-header-on-background-visio"       = "#ffffff";
          "toolbar-header-document"                = "#7c4dff";
          "toolbar-header-pdf"                     = "#7c4dff";
          "toolbar-header-presentation"            = "#7c4dff";
          "toolbar-header-spreadsheet"             = "#7c4dff";
          "toolbar-header-visio"                   = "#7c4dff";
          "window-background"                      = "#141318";
        };
      };

      # Light variant. `values` schema mirrors theme-white.json from
      # upstream, with M3 light values for each role. Includes the
      # extra keys theme-white has (tab-editor-theme-type,
      # tool-button-active-background1).
      themeDmsLight = {
        id = "theme-dms";
        name = "DankMaterialShell";
        type = "light";
        values = {
          "border-control-focus"                        = "#6750a4";
          "brand-cell"                                  = "#6750a4";
          "brand-draw"                                  = "#6750a4";
          "brand-pdf"                                   = "#6750a4";
          "brand-slide"                                 = "#6750a4";
          "brand-word"                                  = "#6750a4";
          "button-normal-opacity"                       = "rgba(49,49,49,255)";
          "download-ghost-button-text"                  = "#9678d4";
          "download-ghost-button-text-hover"            = "#1d1b20";
          "download-ghost-button-text-pressed"          = "#49454f";
          "download-ghost-button-text-pressed-item-hover" = "#49454f";
          "download-item-hover-background"             = "#ece6f0";
          "download-label-text"                         = "#1d1b20";
          "download-label-text-info"                    = "#49454f";
          "download-label-text-info-item-hover"         = "#49454f";
          "download-progressbar-background"             = "#cac4d0";
          "download-progressbar-background-item-hover"  = "#cac4d0";
          "download-progressbar-chunk"                  = "#6750a4";
          "download-scrollbar-handle"                   = "#79747e";
          "download-widget-background"                 = "#f3edf7";
          "download-widget-border"                      = "#cac4d0";
          "logo-type"                                   = "light";
          "menu-background"                             = "#f3edf7";
          "menu-border"                                 = "#cac4d0";
          "menu-item-hover-background"                  = "#ece6f0";
          "menu-separator"                              = "#cac4d0";
          "menu-text"                                   = "#1d1b20";
          "menu-text-item-disabled"                     = "#49454f";
          "menu-text-item-hover"                        = "#ffffff";
          "tab-active-background"                       = "#fef7ff";
          "tab-default-active-background"               = "#fef7ff";
          "tab-default-active-text"                     = "#1d1b20";
          "tab-divider"                                 = "#cac4d0";
          "tab-editor-theme-type"                       = "light";
          "tab-simple-active-background"                = "#fef7ff";
          "tab-simple-active-text"                      = "#1d1b20";
          "text-inverse"                                = "#ffffff";
          "text-normal"                                 = "#1d1b20";
          "text-pretty"                                 = "#1d1b20";
          "tool-button-active-background"               = "#eaddff";
          "tool-button-active-background1"              = "#fef7ff";
          "tool-button-background"                      = "#f7f2fa";
          "tool-button-hover-background"                = "#f3edf7";
          "tool-button-pressed-background"              = "#ece6f0";
          "tooltip-background"                          = "#e6e0ea";
          "tooltip-border"                              = "#cac4d0";
          "tooltip-text"                                = "#1d1b20";
          "window-background"                           = "#fef7ff";
          "window-border"                               = "#cac4d0";
        };
        colors = {
          "background-accent-button"               = "#6750a4";
          "background-contrast-popover"            = "#e6e0ea";
          "background-loader"                      = "#f3edf7";
          "background-normal"                      = "#fef7ff";
          "background-notification-badge"          = "#b3261e";
          "background-notification-popover"        = "#e6e0ea";
          "background-primary-dialog-button"       = "#6750a4";
          "background-scrim"                       = "#000000";
          "background-toolbar"                     = "#f7f2fa";
          "background-toolbar-additional"          = "#f3edf7";
          "border-color-shading"                   = "#cac4d0";
          "border-contrast-popover"                = "#79747e";
          "border-control-focus"                   = "#6750a4";
          "border-divider"                         = "#cac4d0";
          "border-error"                           = "#b3261e";
          "border-preview-hover"                   = "#6750a4";
          "border-preview-select"                  = "#6750a4";
          "border-regular-control"                 = "#cac4d0";
          "border-toolbar"                         = "#cac4d0";
          "border-toolbar-button-hover"            = "#79747e";
          "canvas-anim-pane-background"            = "#e6e0ea";
          "canvas-background"                      = "#fef7ff";
          "canvas-cell-border"                     = "#cac4d0";
          "canvas-cell-title-background"           = "#f3edf7";
          "canvas-cell-title-background-hover"     = "#ece6f0";
          "canvas-cell-title-background-selected"   = "#eaddff";
          "canvas-cell-title-border"               = "#cac4d0";
          "canvas-cell-title-border-hover"         = "#79747e";
          "canvas-cell-title-border-selected"      = "#6750a4";
          "canvas-cell-title-text"                 = "#1d1b20";
          "canvas-content-background"              = "#fef7ff";
          "canvas-dark-cell-title"                 = "#ded8e1";
          "canvas-dark-cell-title-border"          = "#cac4d0";
          "canvas-dark-cell-title-border-hover"    = "#79747e";
          "canvas-dark-cell-title-border-selected" = "#6750a4";
          "canvas-dark-cell-title-hover"           = "#fef7ff";
          "canvas-dark-cell-title-selected"        = "#6750a4";
          "canvas-dark-content-background"         = "#ded8e1";
          "canvas-dark-page-border"                = "#cac4d0";
          "canvas-freeze-line-1px"                 = "#79747e";
          "canvas-freeze-line-2px"                 = "#6750a4";
          "canvas-high-contrast"                   = "#1d1b20";
          "canvas-high-contrast-disabled"          = "#49454f";
          "canvas-page-border"                     = "#cac4d0";
          "canvas-ruler-background"                = "#f7f2fa";
          "canvas-ruler-border"                    = "#cac4d0";
          "canvas-ruler-handle-border"             = "#79747e";
          "canvas-ruler-handle-border-disabled"    = "#cac4d0";
          "canvas-ruler-margins-background"        = "#f3edf7";
          "canvas-ruler-mark"                      = "#49454f";
          "canvas-scroll-arrow"                    = "#49454f";
          "canvas-scroll-arrow-hover"              = "#1d1b20";
          "canvas-scroll-arrow-pressed"            = "#1d1b20";
          "canvas-scroll-thumb"                    = "#cac4d0";
          "canvas-scroll-thumb-border"             = "#ded8e1";
          "canvas-scroll-thumb-border-hover"       = "#ded8e1";
          "canvas-scroll-thumb-border-pressed"     = "#ded8e1";
          "canvas-scroll-thumb-hover"              = "#79747e";
          "canvas-scroll-thumb-pressed"            = "#49454f";
          "canvas-scroll-thumb-target"             = "#6750a4";
          "canvas-scroll-thumb-target-hover"       = "#6750a4";
          "canvas-scroll-thumb-target-pressed"     = "#6750a4";
          "canvas-select-all-icon"                 = "#1d1b20";
          "canvas-sheet-view-cell-background"      = "#f3edf7";
          "canvas-sheet-view-cell-background-hover"= "#ece6f0";
          "canvas-sheet-view-cell-background-pressed" = "#e6e0ea";
          "canvas-sheet-view-cell-title-label"     = "#1d1b20";
          "highlight-accent-button-hover"          = "#21005d";
          "highlight-accent-button-pressed"        = "#eaddff";
          "highlight-button-hover"                 = "#ece6f0";
          "highlight-button-pressed"               = "#e6e0ea";
          "highlight-button-pressed-hover"         = "#e6e0ea";
          "highlight-header-button-hover"          = "#ece6f0";
          "highlight-header-button-pressed"        = "#e6e0ea";
          "highlight-header-tab-underline-document"    = "#6750a4";
          "highlight-header-tab-underline-pdf"         = "#6750a4";
          "highlight-header-tab-underline-presentation"= "#6750a4";
          "highlight-header-tab-underline-spreadsheet" = "#6750a4";
          "highlight-header-tab-underline-visio"       = "#6750a4";
          "highlight-primary-dialog-button-hover"  = "#21005d";
          "highlight-text-select"                  = "#eaddff";
          "highlight-toolbar-tab-underline-document"    = "#6750a4";
          "highlight-toolbar-tab-underline-pdf"         = "#6750a4";
          "highlight-toolbar-tab-underline-presentation"= "#6750a4";
          "highlight-toolbar-tab-underline-spreadsheet" = "#6750a4";
          "highlight-toolbar-tab-underline-visio"       = "#6750a4";
          "icon-contrast-popover"                   = "#1d1b20";
          "icon-inverse"                           = "#f5eff7";
          "icon-normal"                            = "#1d1b20";
          "icon-normal-pressed"                    = "#49454f";
          "icon-notification-badge"                = "#ffffff";
          "icon-success"                           = "#7d5260";
          "icon-toolbar-header"                    = "#ffffff";
          "shadow-contrast-popover"                = "#000000";
          "text-alt-key-hint"                      = "#49454f";
          "text-contrast-background"               = "#1d1b20";
          "text-inverse"                           = "#322f35";
          "text-link"                              = "#6750a4";
          "text-link-active"                       = "#6750a4";
          "text-link-hover"                        = "#6750a4";
          "text-link-visited"                      = "#6750a4";
          "text-normal"                            = "#1d1b20";
          "text-normal-pressed"                    = "#1d1b20";
          "text-secondary"                         = "#49454f";
          "text-tertiary"                          = "#49454f";
          "text-toolbar-header"                    = "#ffffff";
          "text-toolbar-header-on-background-document"    = "#ffffff";
          "text-toolbar-header-on-background-pdf"         = "#ffffff";
          "text-toolbar-header-on-background-presentation"= "#ffffff";
          "text-toolbar-header-on-background-spreadsheet" = "#ffffff";
          "text-toolbar-header-on-background-visio"       = "#ffffff";
          "toolbar-header-document"                = "#6750a4";
          "toolbar-header-pdf"                     = "#6750a4";
          "toolbar-header-presentation"            = "#6750a4";
          "toolbar-header-spreadsheet"             = "#6750a4";
          "toolbar-header-visio"                   = "#6750a4";
          "window-background"                      = "#ded8e1";
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
