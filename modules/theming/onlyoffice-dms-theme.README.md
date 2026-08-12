# OnlyOffice DMS theme — sample `theme-dms.json` shipped via the
# `install-onlyoffice-dms-theme` helper.
#
# This module is intentionally minimal. The previous version of the
# OnlyOffice theming attempt was a tangle of moving parts: a Python
# sync script, a systemd path unit, a wrapper that tried to inject a
# bwrap bind mount at launch, and a runtime bwrap-script patch. It
# also killed the wrapper itself at launch (because `pgrep -f
# "onlyoffice-desktopeditors"` matched the wrapper's own argv) and
# the bwrap-script arg-injection turned out to be a no-op (the bwrap
# script doesn't forward unknown args to bwrap itself). Net result:
# the user couldn't launch OO.
#
# This version:
#   1. Wrapper = pure passthrough. `cd /tmp; exec __BWRAP_PATH__ "$@"`.
#      No sync, no bind mount, no kill.
#   2. `install-onlyoffice-dms-theme` writes a sample theme to
#      `~/.local/share/onlyoffice/desktopeditors/uithemes/` so the
#      C++ `DesktopEditors` binary picks it up at startup.
#   3. `UITheme=theme-dms` is set in `DesktopEditors.conf` so OO
#      activates the theme by default.
#
# ## How OO loads custom themes
#
# Verified by reading the desktop-apps source (`win-linux/src/cthemes.cpp`):
#
#   void CThemesPrivate::searchLocalThemes() {
#       QFileInfoList themes = QDir(qApp->applicationDirPath() + "/uithemes")
#           .entryInfoList(... << "*.json", QDir::Files);
#       themes.append(QDir(Utils::getAppCommonPath() + "/uithemes")
#           .entryInfoList(... << "*.json", QDir::Files));
#       ...
#   }
#
# `Utils::getAppCommonPath()` returns `~/.local/share/onlyoffice/desktopeditors/`
# on Linux. So the user-writable dir is:
#
#   ~/.local/share/onlyoffice/desktopeditors/uithemes/*.json
#
# Each file must be a JSON object with at minimum `id` (alphanumeric +
# dash only) and `name`. Optional: `colors` (CSS variable dict),
# `type` ("light" or "dark"), `l10n`, `icons`.
#
# The same files populate the Settings → Interface theme menu via
# `Common.Controllers.Desktop.localThemes()` in the JS theme registry.
#
# ## Apply mechanism
#
# 1. **C++ side** reads `UITheme` and the matching file at startup.
# 2. **JS side** populates the Settings menu with the same files
#    (via `localThemes()` returning `localThemesToJson()`).
# 3. Switching themes in Settings → Interface theme is **LIVE**:
#    the JS theme registry rebuilds the stylesheet on every selection,
#    no restart required.
# 4. Editing the JSON file on disk has NO effect until OO is
#    restarted (or the user re-picks the theme from the menu, which
#    re-reads the file via `fromFile`).
#
# So: edit `theme-dms.json` colors, restart OO, OR pick the theme
# again from Settings → Interface theme. Both will pick up the change.
#
# ## How to apply the theme
#
# On the target host, after `nixos-rebuild switch`:
#
# ```bash
# install-onlyoffice-dms-theme
# ```
#
# Restart OnlyOffice. Open Settings → Interface theme. Pick
# "DankMaterialShell". Apply is LIVE.
