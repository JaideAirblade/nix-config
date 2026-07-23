# Millennium Steam theme — synced with DMS Theme Sync (matugen) colors.
#
# Uses kuska1's Material-Theme (https://github.com/kuska1/Material-Theme),
# a full Material Design 3 Steam skin with proper selectors for every
# Steam UI surface. We don't write our own CSS — we just generate the
# `matugen.css` color file that Material-Theme's "Matugen" color option
# loads, and configure Millennium to use the theme with that option.
#
# This module:
#   1. Fetches Material-Theme from GitHub into the Nix store
#   2. A sync script copies the theme to ~/.local/share/Steam/millennium/themes/
#      and generates css/main/colors/matugen.css from DMS's dank-colors.css
#   3. Sets millennium's config.json to use Material-Theme with the Matugen
#      color option + Dark/Light appearance
#   4. A systemd user path unit watches dank-colors.css for changes and
#      re-runs the sync, so Steam's colors track the desktop automatically
#
# The matugen.js inside Material-Theme polls matugen.css every 1.5s, so
# when the sync script rewrites the file, running Steam instances pick
# up the new colors without a restart.
{ pkgs, ... }:

let
  # --- Material-Theme (Millennium Steam skin by kuska1) --------------------
  # A full Material Design 3 theme with hundreds of CSS files covering
  # every Steam UI surface. We just need to provide the color variables.
  materialTheme = pkgs.fetchFromGitHub {
    owner = "kuska1";
    repo = "Material-Theme";
    rev = "de1cf855845cf6d7c27c8889965de285b3be2356";
    hash = "sha256-zYnR70t8Xgb1iUdyG9URmZE0HnkEUu4aPAgg/25FzXM=";
  };

  # --- Matugen template ---------------------------------------------------
  # Generates matugen.css with --md-sys-color-* CSS custom properties.
  # Material-Theme's own CSS files consume these variables.
  #
  # iNiR uses app_* color names (app_accent, app_background, etc.) that
  # are its own custom palette mappings. We use the standard matugen
  # Material Design 3 color keywords instead, mapping them to the same
  # --md-sys-color-* names that Material-Theme expects.
  matugenTemplate = pkgs.writeText "millennium-material.css" ''
    :root {
        --theme-color: "Matugen";
        --hue-rotate: 220deg;

        --md-sys-color-primary: rgb({{colors.primary.default.rgb}});
        --md-sys-color-on-primary: rgb({{colors.on_primary.default.rgb}});
        --md-sys-color-primary-container: rgb({{colors.primary_container.default.rgb}});
        --md-sys-color-on-primary-container: rgb({{colors.on_primary_container.default.rgb}});
        --md-sys-color-primary-fixed: rgb({{colors.primary_fixed.default.rgb}});
        --md-sys-color-primary-fixed-dim: rgb({{colors.primary_fixed_dim.default.rgb}});
        --md-sys-color-on-primary-fixed: rgb({{colors.on_primary_fixed.default.rgb}});
        --md-sys-color-on-primary-fixed-variant: rgb({{colors.on_primary_fixed_variant.default.rgb}});

        --md-sys-color-secondary: rgb({{colors.secondary.default.rgb}});
        --md-sys-color-on-secondary: rgb({{colors.on_secondary.default.rgb}});
        --md-sys-color-secondary-container: rgb({{colors.secondary_container.default.rgb}});
        --md-sys-color-on-secondary-container: rgb({{colors.on_secondary_container.default.rgb}});
        --md-sys-color-secondary-fixed: rgb({{colors.secondary_fixed.default.rgb}});
        --md-sys-color-secondary-fixed-dim: rgb({{colors.secondary_fixed_dim.default.rgb}});
        --md-sys-color-on-secondary-fixed: rgb({{colors.on_secondary_fixed.default.rgb}});
        --md-sys-color-on-secondary-fixed-variant: rgb({{colors.on_secondary_fixed_variant.default.rgb}});

        --md-sys-color-tertiary: rgb({{colors.tertiary.default.rgb}});
        --md-sys-color-on-tertiary: rgb({{colors.on_tertiary.default.rgb}});
        --md-sys-color-tertiary-container: rgb({{colors.tertiary_container.default.rgb}});
        --md-sys-color-on-tertiary-container: rgb({{colors.on_tertiary_container.default.rgb}});
        --md-sys-color-tertiary-fixed: rgb({{colors.tertiary_fixed.default.rgb}});
        --md-sys-color-tertiary-fixed-dim: rgb({{colors.tertiary_fixed_dim.default.rgb}});
        --md-sys-color-on-tertiary-fixed: rgb({{colors.on_tertiary_fixed.default.rgb}});
        --md-sys-color-on-tertiary-fixed-variant: rgb({{colors.on_tertiary_fixed_variant.default.rgb}});

        --md-sys-color-error: rgb({{colors.error.default.rgb}});
        --md-sys-color-on-error: rgb({{colors.on_error.default.rgb}});
        --md-sys-color-error-container: rgb({{colors.error_container.default.rgb}});
        --md-sys-color-on-error-container: rgb({{colors.on_error_container.default.rgb}});

        --md-sys-color-background: rgb({{colors.background.default.rgb}});
        --md-sys-color-on-background: rgb({{colors.on_background.default.rgb}});
        --md-sys-color-surface: rgb({{colors.surface.default.rgb}});
        --md-sys-color-on-surface: rgb({{colors.on_surface.default.rgb}});
        --md-sys-color-surface-variant: rgb({{colors.surface_variant.default.rgb}});
        --md-sys-color-on-surface-variant: rgb({{colors.on_surface_variant.default.rgb}});

        --md-sys-color-surface-dim: rgb({{colors.surface_dim.default.rgb}});
        --md-sys-color-surface-bright: rgb({{colors.surface_bright.default.rgb}});
        --md-sys-color-surface-container-lowest: rgb({{colors.surface_container_lowest.default.rgb}});
        --md-sys-color-surface-container-low: rgb({{colors.surface_container_low.default.rgb}});
        --md-sys-color-surface-container: rgb({{colors.surface_container.default.rgb}});
        --md-sys-color-surface-container-high: rgb({{colors.surface_container_high.default.rgb}});
        --md-sys-color-surface-container-highest: rgb({{colors.surface_container_highest.default.rgb}});

        --md-sys-color-outline: rgb({{colors.outline.default.rgb}});
        --md-sys-color-outline-variant: rgb({{colors.outline_variant.default.rgb}});

        --md-sys-color-inverse-surface: rgb({{colors.inverse_surface.default.rgb}});
        --md-sys-color-inverse-on-surface: rgb({{colors.inverse_on_surface.default.rgb}});
        --md-sys-color-inverse-primary: rgb({{colors.inverse_primary.default.rgb}});
        --md-sys-color-shadow: rgb({{colors.shadow.default.rgb}});
        --md-sys-color-scrim: rgb({{colors.scrim.default.rgb}});
        --md-sys-color-surface-tint: rgb({{colors.primary.default.rgb}});
        --md-sys-color-source-color: rgb({{colors.source_color.default.rgb}});
    }
  '';

  # --- Sync script --------------------------------------------------------
  # Copies Material-Theme to the Steam millennium themes directory (if
  # not already present), generates matugen.css from dank-colors.css,
  # and configures millennium to use the theme with the Matugen color
  # option.
  syncScript = pkgs.writeShellScriptBin "sync-millennium-theme" ''
    set -euo pipefail

    XDG_CONFIG_HOME="''${XDG_CONFIG_HOME:-$HOME/.config}"
    STEAM_DIR="$HOME/.local/share/Steam"
    THEME_DIR="$STEAM_DIR/millennium/themes/Material-Theme"
    COLORS_FILE="$XDG_CONFIG_HOME/gtk-4.0/dank-colors.css"
    MILLENNIUM_CONFIG="$XDG_CONFIG_HOME/millennium/config.json"
    STATIC_THEME="${materialTheme}"

    # --- Install Material-Theme if not present ---
    if [[ ! -f "$THEME_DIR/skin.json" ]]; then
      mkdir -p "$STEAM_DIR/millennium/themes"
      cp -rT "$STATIC_THEME" "$THEME_DIR"
      chmod -R u+w "$THEME_DIR"
      echo "Installed Material-Theme to $THEME_DIR"
    fi

    # --- Deploy Material-Theme to skins/ for Steam loopback compatibility ---
    # Material-Theme's matugen.js loads CSS from steamloopback.host/skins/...
    # but Millennium 3.x stores themes in millennium/themes/. Steam's internal
    # web server does NOT follow symlinks, so we copy the theme directory
    # (with -L to dereference any symlinks from the Nix store fetch) to skins/.
    # The "Material Theme is broken" fallback text appears if this path 404s.
    SKINS_DIR="$STEAM_DIR/skins/Material-Theme"
    if [[ ! -f "$SKINS_DIR/skin.json" ]] || [[ "$SKINS_DIR/skin.json" -ot "$THEME_DIR/skin.json" ]]; then
      rm -rf "$SKINS_DIR"
      mkdir -p "$SKINS_DIR"
      cp -rL "$THEME_DIR/." "$SKINS_DIR/"
      echo "Deployed Material-Theme to $SKINS_DIR"
    fi
    # Always update matugen.css in skins/ (it changes when DMS regenerates colors)
    cp -f "$THEME_DIR/css/main/colors/matugen.css" "$SKINS_DIR/css/main/colors/matugen.css" 2>/dev/null || true

    # --- Generate matugen.css from DMS's dank-colors.css ---
    # dank-colors.css has @define-color X #hex — we convert these to
    # the --md-sys-color-* variables that Material-Theme expects.
    #
    # DMS's palette uses GTK/Adwaita naming (window_bg_color, accent_bg_color,
    # etc.) which maps to Material Design 3 surface/primary roles.
    mkdir -p "$THEME_DIR/css/main/colors"

    # Determine if dark or light mode from dank-colors.css content.
    # DMS writes different palettes for light vs dark. We check the
    # accent_fg_color: in dark mode it's dark (e.g. #003060), in light
    # mode it's light. A simple heuristic: if accent_fg_color's luminance
    # is low (dark text on light accent = light mode), it's light mode.
    # Actually the simplest approach: DMS always writes one file, and
    # the mode is determined by the colors themselves. Material-Theme's
    # matugen.css doesn't use scheme-light/scheme-dark — it just has
    # the colors directly. So we map the GTK names to MD3 names.
    generate_matugen_css() {
      local src="$1"

      # Parse @define-color lines into an associative array
      declare -A colors
      local name hex
      while IFS= read -r line; do
        if [[ "$line" =~ @define-color\ ([a-z_]+)\ (#[0-9a-fA-F]+)\; ]]; then
          name="''${BASH_REMATCH[1]}"
          hex="''${BASH_REMATCH[2]}"
          colors[$name]="$hex"
        fi
      done < "$src"

      # Convert hex (#rrggbb) to "r, g, b" for CSS rgb() syntax
      hex_to_rgb() {
        local h="''${1#\#}"
        printf '%d, %d, %d' \
          "0x''${h:0:2}" "0x''${h:2:2}" "0x''${h:4:2}"
      }

      # Map DMS's GTK @define-color names to Material-Theme's
      # --md-sys-color-* variables. DMS's palette follows the
      # Adwaita/GTK naming convention with Material Design color roles.
      cat <<EOF
    :root {
        --theme-color: "Matugen";
        --hue-rotate: 220deg;

        --md-sys-color-primary: rgb($(hex_to_rgb "''${colors[accent_bg_color]:-#a6c8ff}"));
        --md-sys-color-on-primary: rgb($(hex_to_rgb "''${colors[accent_fg_color]:-#003060}"));
        --md-sys-color-primary-container: rgb($(hex_to_rgb "''${colors[accent_bg_color]:-#a6c8ff}"));
        --md-sys-color-on-primary-container: rgb($(hex_to_rgb "''${colors[accent_fg_color]:-#003060}"));
        --md-sys-color-primary-fixed: rgb($(hex_to_rgb "''${colors[accent_bg_color]:-#a6c8ff}"));
        --md-sys-color-primary-fixed-dim: rgb($(hex_to_rgb "''${colors[accent_bg_color]:-#a6c8ff}"));
        --md-sys-color-on-primary-fixed: rgb($(hex_to_rgb "''${colors[accent_fg_color]:-#003060}"));
        --md-sys-color-on-primary-fixed-variant: rgb($(hex_to_rgb "''${colors[accent_fg_color]:-#003060}"));

        --md-sys-color-secondary: rgb($(hex_to_rgb "''${colors[card_bg_color]:-#1b2029}"));
        --md-sys-color-on-secondary: rgb($(hex_to_rgb "''${colors[card_fg_color]:-#dee2ef}"));
        --md-sys-color-secondary-container: rgb($(hex_to_rgb "''${colors[card_bg_color]:-#1b2029}"));
        --md-sys-color-on-secondary-container: rgb($(hex_to_rgb "''${colors[card_fg_color]:-#dee2ef}"));
        --md-sys-color-secondary-fixed: rgb($(hex_to_rgb "''${colors[card_bg_color]:-#1b2029}"));
        --md-sys-color-secondary-fixed-dim: rgb($(hex_to_rgb "''${colors[card_bg_color]:-#1b2029}"));
        --md-sys-color-on-secondary-fixed: rgb($(hex_to_rgb "''${colors[card_fg_color]:-#dee2ef}"));
        --md-sys-color-on-secondary-fixed-variant: rgb($(hex_to_rgb "''${colors[card_fg_color]:-#dee2ef}"));

        --md-sys-color-tertiary: rgb($(hex_to_rgb "''${colors[popover_bg_color]:-#1b2029}"));
        --md-sys-color-on-tertiary: rgb($(hex_to_rgb "''${colors[popover_fg_color]:-#dee2ef}"));
        --md-sys-color-tertiary-container: rgb($(hex_to_rgb "''${colors[popover_bg_color]:-#1b2029}"));
        --md-sys-color-on-tertiary-container: rgb($(hex_to_rgb "''${colors[popover_fg_color]:-#dee2ef}"));
        --md-sys-color-tertiary-fixed: rgb($(hex_to_rgb "''${colors[popover_bg_color]:-#1b2029}"));
        --md-sys-color-tertiary-fixed-dim: rgb($(hex_to_rgb "''${colors[popover_bg_color]:-#1b2029}"));
        --md-sys-color-on-tertiary-fixed: rgb($(hex_to_rgb "''${colors[popover_fg_color]:-#dee2ef}"));
        --md-sys-color-on-tertiary-fixed-variant: rgb($(hex_to_rgb "''${colors[popover_fg_color]:-#dee2ef}"));

        --md-sys-color-error: rgb($(hex_to_rgb "''${colors[error_bg_color]:-#ffb4ab}"));
        --md-sys-color-on-error: rgb($(hex_to_rgb "''${colors[error_fg_color]:-#690005}"));
        --md-sys-color-error-container: rgb($(hex_to_rgb "''${colors[error_bg_color]:-#ffb4ab}"));
        --md-sys-color-on-error-container: rgb($(hex_to_rgb "''${colors[error_fg_color]:-#690005}"));

        --md-sys-color-background: rgb($(hex_to_rgb "''${colors[window_bg_color]:-#0e141c}"));
        --md-sys-color-on-background: rgb($(hex_to_rgb "''${colors[window_fg_color]:-#dee2ef}"));
        --md-sys-color-surface: rgb($(hex_to_rgb "''${colors[view_bg_color]:-#0e141c}"));
        --md-sys-color-on-surface: rgb($(hex_to_rgb "''${colors[view_fg_color]:-#dee2ef}"));
        --md-sys-color-surface-variant: rgb($(hex_to_rgb "''${colors[sidebar_bg_color]:-#1b2029}"));
        --md-sys-color-on-surface-variant: rgb($(hex_to_rgb "''${colors[sidebar_fg_color]:-#dee2ef}"));

        --md-sys-color-surface-dim: rgb($(hex_to_rgb "''${colors[window_bg_color]:-#0e141c}"));
        --md-sys-color-surface-bright: rgb($(hex_to_rgb "''${colors[popover_bg_color]:-#1b2029}"));
        --md-sys-color-surface-container-lowest: rgb($(hex_to_rgb "''${colors[window_bg_color]:-#0e141c}"));
        --md-sys-color-surface-container-low: rgb($(hex_to_rgb "''${colors[sidebar_bg_color]:-#1b2029}"));
        --md-sys-color-surface-container: rgb($(hex_to_rgb "''${colors[card_bg_color]:-#1b2029}"));
        --md-sys-color-surface-container-high: rgb($(hex_to_rgb "''${colors[sidebar_bg_color]:-#1b2029}"));
        --md-sys-color-surface-container-highest: rgb($(hex_to_rgb "''${colors[popover_bg_color]:-#1b2029}"));

        --md-sys-color-outline: rgb($(hex_to_rgb "''${colors[window_fg_color]:-#dee2ef}"));
        --md-sys-color-outline-variant: rgb($(hex_to_rgb "''${colors[card_bg_color]:-#1b2029}"));

        --md-sys-color-inverse-surface: rgb($(hex_to_rgb "''${colors[window_fg_color]:-#dee2ef}"));
        --md-sys-color-inverse-on-surface: rgb($(hex_to_rgb "''${colors[window_bg_color]:-#0e141c}"));
        --md-sys-color-inverse-primary: rgb($(hex_to_rgb "''${colors[accent_bg_color]:-#a6c8ff}"));
        --md-sys-color-shadow: rgb(0, 0, 0);
        --md-sys-color-scrim: rgb(0, 0, 0);
        --md-sys-color-surface-tint: rgb($(hex_to_rgb "''${colors[accent_bg_color]:-#a6c8ff}"));
        --md-sys-color-source-color: rgb($(hex_to_rgb "''${colors[accent_bg_color]:-#a6c8ff}"));
    }
    EOF
    }

    # Generate matugen.css from dank-colors.css if it exists,
    # otherwise use fallback defaults matching DMS's dark palette.
    if [[ -f "$COLORS_FILE" ]]; then
      generate_matugen_css "$COLORS_FILE" > "$THEME_DIR/css/main/colors/matugen.css"
    else
      # Fallback: use the matugen.css that shipped with Material-Theme
      # (it has reasonable default colors)
      cp -f "$STATIC_THEME/css/main/colors/matugen.css" "$THEME_DIR/css/main/colors/matugen.css"
    fi

    # --- Inject matugen color variables into root-colors.css ---
    # Material-Theme's "broken" fallback text in library.css becomes visible
    # when --md-sys-color-* variables are undefined. The matugen.js loads
    # matugen.css via a <link> element AFTER the page renders, causing a
    # brief flash of the "broken" text. By injecting the variables into
    # root-colors.css (which Millennium loads via its CSS injection system,
    # before any JS runs), the variables are available from first paint.
    inject_root_colors() {
      local root_colors="$THEME_DIR/css/main/root-colors.css"
      local matugen_css="$THEME_DIR/css/main/colors/matugen.css"
      if [[ ! -f "$root_colors" || ! -f "$matugen_css" ]]; then
        return
      fi
      # Restore the original root-colors.css from the static theme, then
      # append the --md-sys-color-* variables inside the :root block.
      cp -f "$STATIC_THEME/css/main/root-colors.css" "$root_colors"
      # Extract the --md-sys-color-* lines from matugen.css and insert
      # them before the final closing brace of root-colors.css.
      local vars
      vars=$(grep -E '^\s+--md-sys-color-' "$matugen_css" || true)
      if [[ -n "$vars" ]]; then
        # Remove the last line (closing }) and append vars + new closing brace
        local last_line
        last_line=$(tail -1 "$root_colors")
        if [[ "$last_line" == "}" ]]; then
          head -n -1 "$root_colors" > "$root_colors.tmp"
          printf '%s\n}\n' "$vars" >> "$root_colors.tmp"
          mv "$root_colors.tmp" "$root_colors"
        fi
      fi
    }
    inject_root_colors
    # Copy the injected root-colors.css to skins/ too
    cp -f "$THEME_DIR/css/main/root-colors.css" "$SKINS_DIR/css/main/root-colors.css" 2>/dev/null || true

    # --- Configure Millennium to use Material-Theme with Matugen colors ---
    if command -v python3 >/dev/null 2>&1; then
      python3 - "$MILLENNIUM_CONFIG" <<'PYCFG'
    import json, os, sys
    path = sys.argv[1]
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        data = {}

    data.setdefault("general", {})
    data["general"]["injectCSS"] = True
    data["general"]["injectJavascript"] = True

    data.setdefault("themes", {})
    data["themes"]["activeTheme"] = "Material-Theme"
    data["themes"]["allowedStyles"] = True
    data["themes"]["allowedScripts"] = True

    conditions = data["themes"].setdefault("conditions", {})
    material = conditions.setdefault("Material-Theme", {})
    material["Color"] = "Matugen"
    # Appearance: Dark is the default; the sync script will update
    # this to Light when DMS is in light mode (future enhancement).
    material["Appearance"] = "Dark"

    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
    PYCFG
      echo "Configured Millennium to use Material-Theme with Matugen colors"
    else
      echo "WARNING: python3 not found — Millennium config not updated"
    fi

    echo "Millennium Material-Theme synced to $THEME_DIR"
  '';

  # --- Matugen config -----------------------------------------------------
  # Placed at ~/.config/matugen/config.toml so manual `matugen image`
  # runs also regenerate the Steam theme colors.
  matugenConfig = pkgs.writeText "config.toml" ''
    [config]

    [templates.millennium]
    input_path = '~/.config/matugen/templates/millennium-material.css'
    output_path = '~/.local/share/Steam/millennium/themes/Material-Theme/css/main/colors/matugen.css'
    post_hook = '${syncScript}/bin/sync-millennium-theme'
  '';
in {
  environment.systemPackages = [ pkgs.matugen ];

  # Systemd user service — runs on login to deploy the theme and sync
  # colors. Also symlinks the matugen config + template into ~/.config/.
  systemd.user.services.millennium-theme-sync = {
    description = "Sync DMS matugen colors to Millennium Material-Theme";
    after = [ "graphical-session.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # python3 is needed by the sync script to update millennium's config.json
    path = [ pkgs.python3 ];
    preStart = ''
      ${pkgs.coreutils}/bin/mkdir -p "$HOME/.config/matugen/templates"
      ${pkgs.coreutils}/bin/ln -sf "${matugenConfig}" "$HOME/.config/matugen/config.toml"
      ${pkgs.coreutils}/bin/ln -sf "${matugenTemplate}" "$HOME/.config/matugen/templates/millennium-material.css"
    '';
    script = "${syncScript}/bin/sync-millennium-theme";
  };

  # Watch dank-colors.css for changes → re-sync the theme automatically.
  systemd.user.paths.millennium-theme-sync = {
    description = "Watch dank-colors.css for Millennium theme sync";
    wantedBy = [ "default.target" ];
    pathConfig = {
      PathChanged = [ "%h/.config/gtk-4.0/dank-colors.css" ];
    };
  };
}