# Legcord DMS theme sync — System24 layout colored by the live DMS palette.
#
# Legcord natively loads and watches ~/.config/legcord/quickCss.css. This
# module regenerates that file from DankMaterialShell's palette cache
# (colors.dark / colors.light, selected by matching the GTK background)
# whenever DMS changes wallpaper or light/dark mode.
#
# Write semantics matter: Legcord's fs.watch only reacts to the "change"
# event, not "rename". The generator therefore overwrites quickCss.css in
# place (preserving its inode); atomic tmp+rename would leave a running
# client stuck on the old stylesheet.
_:
{
  nixos.modules.common =
    { pkgs, ... }:

    let
      # E501: the embedded CSS template intentionally uses long lines.
      syncScript = pkgs.writers.writePython3Bin "sync-legcord-dms-theme"
        {
          flakeIgnore = [ "E501" ];
        } ''
        import json
        import os
        import re
        from pathlib import Path

        HEX_COLOR = re.compile(r"^#[0-9a-fA-F]{6}$")


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


        home = Path.home()
        config_home = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
        cache_home = Path(os.environ.get("XDG_CACHE_HOME", home / ".cache"))
        palette_path = cache_home / "DankMaterialShell" / "dms-colors.json"
        gtk_palette_path = config_home / "gtk-4.0" / "dank-colors.css"
        output_path = config_home / "legcord" / "quickCss.css"

        with palette_path.open(encoding="utf-8") as palette_file:
            cache = json.load(palette_file)

        gtk_colors = {
            name: value
            for name, value in re.findall(
                r"@define-color\s+([a-z_]+)\s+(#[0-9a-fA-F]{6})\s*;",
                gtk_palette_path.read_text(encoding="utf-8"),
            )
        }
        colors = cache["colors"][active_mode(cache, gtk_colors)]

        background = require_color(colors, "background")
        surface_lowest = require_color(colors, "surface_container_lowest")
        surface_low = require_color(colors, "surface_container_low")
        surface = require_color(colors, "surface_container")
        surface_high = require_color(colors, "surface_container_high")
        surface_highest = require_color(colors, "surface_container_highest")
        on_surface = require_color(colors, "on_surface")
        on_surface_variant = require_color(colors, "on_surface_variant")
        primary = require_color(colors, "primary")
        primary_container = require_color(colors, "primary_container")
        primary_fixed = require_color(colors, "primary_fixed")
        on_primary = require_color(colors, "on_primary")
        secondary = require_color(colors, "secondary")
        tertiary = require_color(colors, "tertiary")
        error = require_color(colors, "error")
        outline = require_color(colors, "outline")

        css = f"""/*
         * Legcord DMS System24
         *
         * Managed by NixOS: modules/theming/legcord-dms-theme.nix
         * Base styling: refact0r/system24, as used by snowarch/iNiR.
         * Palette: the active DankMaterialShell Material color roles.
         */
        @import url("https://refact0r.github.io/system24/build/system24.css");

        body {{
          /* Keep Discord's native typography; use System24 for the layout. */
          --font: "";
          --code-font: "";
          font-weight: 400;
          letter-spacing: normal;

          --gap: 10px;
          --divider-thickness: 2px;
          --border-thickness: 1px;
          --border-hover-transition: 0.2s ease;
          --animations: on;
          --list-item-transition: 0.2s ease;

          --top-bar-height: 36px;
          --top-bar-button-position: off;
          --top-bar-title-position: off;
          --subtle-top-bar-title: off;
          --custom-window-controls: off;
          --custom-dms-icon: off;
          --custom-dms-background: color;
          --dms-background-color: var(--accent-2);

          --background-image: off;
          --transparency-tweaks: off;
          --remove-bg-layer: off;
          --panel-blur: off;
          --bg-floating: var(--bg-1);
          --small-user-panel: on;
          --unrounding: off;
          --custom-spotify-bar: on;
          --ascii-titles: off;
          --ascii-loader: off;
          --panel-labels: off;
        }}

        :root, :root:root, body, #app-mount {{
          --colors: on;

          /* DMS surfaces and text hierarchy. */
          --text-0: {on_primary};
          --text-1: {on_surface};
          --text-2: {on_surface};
          --text-3: {on_surface_variant};
          --text-4: {on_surface_variant};
          --text-5: {outline};
          --bg-4: {background};
          --bg-3: {surface_low};
          --bg-2: {surface};
          --bg-1: {surface_high};
          --bg-floating: {surface_highest};

          /* DMS primary drives Discord's accent and interaction states. */
          --accent-1: {primary_fixed};
          --accent-2: {primary};
          --accent-3: {primary};
          --accent-4: {primary};
          --accent-5: {primary_container};
          --accent-new: {primary};
          --hover: color-mix(in srgb, {primary} 12%, transparent);
          --active: color-mix(in srgb, {primary} 20%, transparent);
          --active-2: color-mix(in srgb, {primary} 28%, transparent);
          --message-hover: color-mix(in srgb, {primary} 8%, transparent);
          --mention: linear-gradient(to right, color-mix(in srgb, {primary} 18%, transparent) 40%, transparent);
          --mention-hover: linear-gradient(to right, color-mix(in srgb, {primary} 26%, transparent) 40%, transparent);
          --reply: linear-gradient(to right, color-mix(in srgb, {on_surface_variant} 16%, transparent) 40%, transparent);
          --reply-hover: linear-gradient(to right, color-mix(in srgb, {on_surface_variant} 24%, transparent) 40%, transparent);

          /* Material semantic roles, following iNiR's System24 mapping. */
          --online: {tertiary};
          --dnd: {error};
          --idle: {secondary};
          --streaming: color-mix(in srgb, {tertiary} 70%, {primary});
          --offline: {outline};
          --border-light: color-mix(in srgb, {outline} 14%, transparent);
          --border: color-mix(in srgb, {outline} 25%, transparent);
          --border-hover: color-mix(in srgb, {primary} 52%, {outline});
          --button-border: color-mix(in srgb, {outline} 20%, transparent);

          --red-1: {error};
          --red-2: {error};
          --red-3: {error};
          --red-4: {error};
          --red-5: {error};
          --green-1: {tertiary};
          --green-2: {tertiary};
          --green-3: {tertiary};
          --green-4: {tertiary};
          --green-5: {tertiary};
          --blue-1: {secondary};
          --blue-2: {secondary};
          --blue-3: {secondary};
          --blue-4: {secondary};
          --blue-5: {secondary};
          --yellow-1: color-mix(in srgb, {primary} 65%, {tertiary});
          --yellow-2: color-mix(in srgb, {primary} 65%, {tertiary});
          --yellow-3: color-mix(in srgb, {primary} 65%, {tertiary});
          --yellow-4: color-mix(in srgb, {primary} 65%, {tertiary});
          --yellow-5: color-mix(in srgb, {primary} 65%, {tertiary});
          --purple-1: color-mix(in srgb, {primary} 55%, {secondary});
          --purple-2: color-mix(in srgb, {primary} 55%, {secondary});
          --purple-3: color-mix(in srgb, {primary} 55%, {secondary});
          --purple-4: color-mix(in srgb, {primary} 55%, {secondary});
          --purple-5: color-mix(in srgb, {primary} 55%, {secondary});

          /* Discord still references these directly in some current views. */
          --brand-360: {primary_fixed};
          --brand-400: {primary};
          --brand-500: {primary};
          --brand-560: {primary};
          --brand-600: {primary_container};
        }}

        /* Keep System24's root background aligned with DMS's deepest surface. */
        #app-mount, .appMount__51fd7 {{
          --background-base-lowest: {surface_lowest};
          --background-base-low: {surface_low};
          --background-base-lower: {surface};
          --background-base: {background};
          --background-surface-high: {surface_high};
          --background-surface-higher: {surface_highest};
        }}

        /* Discord added container-type:inline-size to .sidebarList__5e434
         * (around 2026-07-30). The sidebar is now the nearest query container
         * for its descendants, which shadows midnight's @container body
         * style(--small-user-panel: on) block for the user panel inside it.
         * These ungated duplicates of that block restore the docking; placed
         * last so they win the cascade on equal specificity. */
        .panels__5e434 {{
          right: 0;
          left: unset;
          width: calc(var(--custom-guild-sidebar-width) - var(--custom-guild-list-width));
        }}
        .guilds__5e434 {{
          margin-bottom: 0;
        }}
        """

        output_path.parent.mkdir(parents=True, exist_ok=True)
        if not output_path.exists() or output_path.read_text(encoding="utf-8") != css:
            # Legcord watches quickCss.css, but its watcher only handles the
            # "change" event. Replacing the file atomically emits "rename",
            # leaving a running client on the old stylesheet. An in-place write
            # preserves the watched inode and emits the event Legcord reloads.
            output_path.write_text(css, encoding="utf-8")
      '';
    in
    {
      # Oneshot that regenerates quickCss.css from the current DMS palette.
      # Debounced ~2s so DMS's cache/CSS writes have settled before parsing.
      systemd.user.services.legcord-dms-theme-sync = {
        description = "Sync Legcord System24 colors with DankMaterialShell";
        after = [ "graphical-session.target" ];
        wantedBy = [ "default.target" ];
        serviceConfig = {
          Type = "oneshot";
          Restart = "on-failure";
          RestartSec = "2s";
        };
        script = ''
          sleep 2
          exec ${syncScript}/bin/sync-legcord-dms-theme
        '';
      };

      # Watch the DMS palette cache and generated GTK colors. DMS updates
      # these atomically, so watch the parent directories rather than the
      # individual files.
      systemd.user.paths.legcord-dms-theme-sync = {
        description = "Watch DMS palette changes for Legcord";
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
