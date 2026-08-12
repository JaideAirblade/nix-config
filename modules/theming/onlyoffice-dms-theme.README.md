# OnlyOffice DMS theme — sample `theme-dms.json` shipped in the package
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
#   1. Ships a sample `theme-dms.json` in the package's resources.
#   2. Ships `install-onlyoffice-dms-theme` that writes the theme into
#      the user's `~/.config/onlyoffice/DesktopEditors.conf` so it
#      appears in Settings → Interface theme.
#   3. Pure-passthrough wrapper (no sync, no bind mount, no kill).
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
# "DankMaterialShell". Apply is LIVE (the JS theme registry rebuilds
# the stylesheet on selection — see
# `editors/web-apps/apps/common/main/lib/controller/Themes.js`).
#
# ## Apply mechanism (what the user wanted to verify)
#
# 1. **C++ side** (`DesktopEditors` binary) reads the `localthemes`
#    QSettings value from `~/.config/onlyoffice/DesktopEditors.conf`
#    at startup. The blob is a JSON object with a `themes` array.
# 2. **JS side** (`Common.Controllers.Desktop.localThemes()`) returns
#    that blob to the theme registry in
#    `editors/web-apps/apps/common/main/lib/controller/Themes.js`.
# 3. The registry is populated once at startup. CEF does NOT watch
#    `localthemes` for changes — edits to the JSON only take effect
#    on the next OO launch.
# 4. Switching themes in the Settings menu is LIVE: the
#    `apply_icons_from_url` / stylesheet-injection code in
#    `Themes.js` rebuilds the stylesheet on every selection.
#
# So: edit `theme-dms.json` colors, restart OO, OR pick the theme
# again from Settings → Interface theme. Both will pick up the change.
#
# ## Theme file format
#
# Each entry in the `themes` array:
#
# ```json
# {
#   "id": "theme-dms",
#   "name": "DankMaterialShell",
#   "type": "dark",
#   "colors": {
#     "background-toolbar": "#1c1b1f",
#     "toolbar-header-document": "#7c4dff",
#     ...
#   }
# }
# ```
#
# The full list of valid color keys is the `s` array in
# `editors/web-apps/apps/common/main/lib/controller/Themes.js`. The
# subset used in `theme-dms.json` covers the visible chrome (toolbar,
# header, sidebar, menus, scrollbars, buttons). Add more keys as
# needed — unknown keys are silently ignored, so it's safe to include
# the full set.
