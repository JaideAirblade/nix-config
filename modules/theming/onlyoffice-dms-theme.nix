# OnlyOffice DMS theme sync — paint the OnlyOffice chrome with the active
# DankMaterialShell palette.
#
# OnlyOffice Desktop Editors is a Chromium Embedded Framework (CEF) app.
# Its entire UI theme lives in `/usr/share/desktopeditors/index.html`
# (1.1 MiB, ~200 KB of compiled CSS) as CSS custom properties keyed by
# `theme-{name}` class on <html>: `theme-dark`, `theme-night`, `theme-
# contrast`, `theme-gray`, `theme-white`, `theme-classic`. The user picks
# the active class via Settings → Interface theme; we override the
# variables to paint DMS colors regardless of which class is selected.
#
# Why this is gnarly:
#
#   - `index.html` lives in /nix/store/<fhsenv>/usr/share/desktopeditors/
#     which is read-only.
#   - CEF loads index.html from a path embedded in the DesktopEditors
#     binary at compile time. No CLI flag, env var, or config option
#     redirects it. Chromium's `Custom.css` convention requires a flag
#     CEF doesn't expose here, so that doesn't work either.
#   - OnlyOffice's NixOS package is wrapped by buildFHSEnv, which uses
#     bwrap to mount the FHS rootfs into a private namespace. The bwrap
#     script does `--ro-bind <fhsenv>/usr/share/desktopeditors
#     /usr/share/desktopeditors` — read-only.
#
# The hook we use: bwrap processes bind mounts left-to-right and later
# mounts shadow earlier ones. We add a SECOND `--bind` (writable) of
# `$HOME/.cache/onlyoffice-themes/desktopeditors` over the read-only
# mount. CEF then reads our patched index.html from the user cache.
#
# Mechanics:
#   1. The NixOS module replaces the symlink at `$out/bin/onlyoffice-
#      desktopeditors` (which points to the bwrap script) with a wrapper
#      script. The wrapper runs the palette sync, then re-execs the
#      original bwrap script with `--bind` prepended.
#   2. The sync reads `~/.cache/DankMaterialShell/dms-colors.json`,
#      renders the DMS→OnlyOffice CSS map, mirrors the FHS rootfs share
#      tree into `~/.cache/onlyoffice-themes/desktopeditors/`, and
#      in-place patches the cached `index.html` (inserting before
#      `</head>` with begin/end markers so re-runs replace the same
#      block rather than accumulating copies).
#   3. If OnlyOffice is currently running, the sync kills it before
#      patching (CEF holds the index.html file handle open; new content
#      is only visible on next launch). The user's working documents
#      are in CEF localStorage which CEF flushes on SIGTERM.
#   4. A systemd user path unit watches `~/.cache/DankMaterialShell`
#      and `~/.cache/onlyoffice-themes` and re-runs the sync whenever
#      DMS updates its palette cache.
#
# The mode-selection heuristic matches the Legcord module: pick the DMS
# palette variant whose `background` color matches the GTK window-bg
# color. This naturally follows the user's DMS light/dark mode flip.
_:
{
  nixos.modules.common =
    { pkgs, ... }:

    let
      # CSS map: material-design-3 token → OnlyOffice CSS variable. The
      # variable names are taken from `/usr/share/desktopeditors/index.html`
      # in the OnlyOffice 9.1.0 source; the same names appear in every
      # theme-{dark,night,white,contrast,gray,classic} variant block.
      #
      # Variables we deliberately leave alone:
      #   - `--border-radius-*` (cosmetic — not color)
      #   - `--scaled-one-px` (cosmetic)
      #   - `--theme-inverted-image-filter` (image filter, not color)
      cssTemplate = ''
        :root {
          --background-normal:           __SURFACE__;
          --background-normal-element:   __SURFACE__;
          --background-tabbar:           __SURFACE__;
          --background-action-panel:     __SURFACE_CONTAINER__;
          --background-icon-normal:      __SURFACE_CONTAINER__;
          --background-primary-button:   __PRIMARY__;
          --background-scrim:            rgba(0, 0, 0, 0.6);
          --background-scroll-thumb:     __SURFACE_CONTAINER_HIGH__;

          --background-accent-button:    __PRIMARY__;
          --highlight-accent-button-hover: __PRIMARY_CONTAINER__;
          --highlight-accent-button-pressed: __PRIMARY_CONTAINER__;
          --highlight-text-select:       __PRIMARY__;
          --highlight-toolbar-tab-underline-document: __PRIMARY__;

          --highlight-button-hover:      __SURFACE_CONTAINER_HIGH__;
          --highlight-button-pressed:    __SURFACE_CONTAINER_HIGHEST__;
          --highlight-button-pressed-hover: __SURFACE_CONTAINER_HIGHEST__;
          --highlight-primary-button-hover: __PRIMARY__;
          --highlight-primary-button-pressed: __PRIMARY_CONTAINER__;

          --border-divider:              __OUTLINE_VARIANT__;
          --border-regular-control:      __OUTLINE__;
          --border-control-focus:        __PRIMARY__;
          --border-tabbar:               __OUTLINE_VARIANT__;
          --border-sidebar:              __OUTLINE_VARIANT__;
          --border-sidebar-icon:         __OUTLINE_VARIANT__;
          --border-error:                __ERROR__;

          --text-normal:                 __ON_SURFACE__;
          --text-normal-pressed:         __ON_SURFACE__;
          --text-secondary:              __ON_SURFACE_VARIANT__;
          --text-tertiary:               __ON_SURFACE_VARIANT__;
          --text-link:                   __PRIMARY__;
          --text-inverse:                __ON_PRIMARY__;
          --text-contrast-background:    __SURFACE__;
          --text-negative:               __ERROR__;

          --icon-normal:                 __ON_SURFACE__;
          --icon-success:                __TERTIARY__;
        }
        /* Override each built-in theme variant too — same variables, but
         * keeps hover accents consistent regardless of which theme class
         * the user has selected in Settings → Interface theme. */
        :root .theme-dark, :root .theme-night, :root .theme-contrast,
        :root .theme-gray {
          --background-normal:           __SURFACE__;
          --background-tabbar:           __SURFACE__;
          --background-action-panel:     __SURFACE_CONTAINER__;
          --background-icon-normal:      __SURFACE_CONTAINER__;
          --background-primary-button:   __PRIMARY__;
          --background-scroll-thumb:     __SURFACE_CONTAINER_HIGH__;
          --background-accent-button:    __PRIMARY__;
          --highlight-text-select:       __PRIMARY__;
          --highlight-toolbar-tab-underline-document: __PRIMARY__;
          --border-divider:              __OUTLINE_VARIANT__;
          --border-regular-control:      __OUTLINE__;
          --border-tabbar:               __OUTLINE_VARIANT__;
          --text-normal:                 __ON_SURFACE__;
          --text-secondary:              __ON_SURFACE_VARIANT__;
          --text-tertiary:               __ON_SURFACE_VARIANT__;
          --text-link:                   __PRIMARY__;
          --text-inverse:                __ON_PRIMARY__;
          --icon-normal:                 __ON_SURFACE__;
          --icon-success:                __TERTIARY__;
        }
        :root .theme-white, :root .theme-classic-light {
          --background-normal:           __L_SURFACE__;
          --background-tabbar:           __L_SURFACE__;
          --background-action-panel:     __L_SURFACE_CONTAINER__;
          --background-icon-normal:      __L_SURFACE__;
          --background-primary-button:   __L_PRIMARY__;
          --background-scroll-thumb:     __L_OUTLINE_VARIANT__;
          --background-accent-button:    __L_PRIMARY__;
          --highlight-text-select:       __L_PRIMARY__;
          --highlight-toolbar-tab-underline-document: __L_PRIMARY__;
          --border-divider:              __L_OUTLINE_VARIANT__;
          --border-regular-control:      __L_OUTLINE__;
          --border-tabbar:               __L_OUTLINE_VARIANT__;
          --text-normal:                 __L_ON_SURFACE__;
          --text-normal-pressed:         __L_ON_SURFACE__;
          --text-secondary:              __L_ON_SURFACE_VARIANT__;
          --text-tertiary:               __L_ON_SURFACE_VARIANT__;
          --text-link:                   __L_PRIMARY__;
          --text-inverse:                __L_ON_PRIMARY__;
          --icon-normal:                 __L_ON_SURFACE__;
          --icon-success:                __L_TERTIARY__;
        }
      '';

      # Python sync script — runs as a user systemd oneshot. Mirrors the
      # shape of `sync-legcord-dms-theme` / `sync-readest-dms-theme` for
      # consistency.
      syncScript = pkgs.writers.writePython3Bin "sync-onlyoffice-dms-theme"
        {
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
        MARKER_BEGIN = "/* __ONLYOFFICE_DMS_THEME_BEGIN__ */"
        MARKER_END = "/* __ONLYOFFICE_DMS_THEME_END__ */"

        # OnlyOffice's NixOS wrapper invokes a bwrap script whose first
        # argument is a realpath pointing at the FHS rootfs. We discover
        # the share dir by walking from the wrapper script up to the
        # fhsenv-profile store path and finding usr/share/desktopeditors.
        #
        # The bwrap script iterates over the FHS rootfs contents and
        # adds a read-only bind mount for each entry (so the CEF binary
        # sees /usr/share/desktopeditors/index.html). The fhsenv rootfs
        # path is embedded in the bwrap script source as a regex-matchable
        # literal; we discover it at runtime.
        OO_BWRAP_SCRIPT = Path(
            "/nix/store/4dbx9yyy56f3crjj6ddzz813h8qs1q5c-onlyoffice-desktopeditors-9.1.0-fhsenv-profile/bin/onlyoffice-desktopeditors"
        )

        # The CSS template is embedded as a JSON-encoded literal so the
        # Python source can do straight string replace on the placeholders.
        TEMPLATE = json.loads('''${builtins.toJSON cssTemplate}''')


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


        def render_css(palette_dark, palette_light):
            out = TEMPLATE
            mapping = {
                "SURFACE":               palette_dark["surface"],
                "SURFACE_CONTAINER":     palette_dark["surface_container"],
                "SURFACE_CONTAINER_HIGH":palette_dark["surface_container_high"],
                "SURFACE_CONTAINER_HIGHEST": palette_dark["surface_container_highest"],
                "PRIMARY":               palette_dark["primary"],
                "PRIMARY_CONTAINER":     palette_dark["primary_container"],
                "ON_PRIMARY":            palette_dark["on_primary"],
                "ON_SURFACE":            palette_dark["on_surface"],
                "ON_SURFACE_VARIANT":    palette_dark["on_surface_variant"],
                "OUTLINE":               palette_dark["outline"],
                "OUTLINE_VARIANT":       palette_dark["outline_variant"],
                "ERROR":                 palette_dark["error"],
                "TERTIARY":              palette_dark["tertiary"],
                "L_SURFACE":             palette_light["surface"],
                "L_SURFACE_CONTAINER":   palette_light["surface_container"],
                "L_PRIMARY":             palette_light["primary"],
                "L_ON_PRIMARY":          palette_light["on_primary"],
                "L_ON_SURFACE":          palette_light["on_surface"],
                "L_ON_SURFACE_VARIANT":  palette_light["on_surface_variant"],
                "L_OUTLINE":             palette_light["outline"],
                "L_OUTLINE_VARIANT":     palette_light["outline_variant"],
                "L_TERTIARY":            palette_light["tertiary"],
            }
            for token, hex_value in mapping.items():
                out = out.replace(f"__{token}__", hex_value.lower())
            return out


        def find_share_dir():
            try:
                text = OO_BWRAP_SCRIPT.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                return None
            m = re.search(
                r"/nix/store/[\w-]+-onlyoffice-desktopeditors-[\w.-]+/\*",
                text,
            )
            if not m:
                return None
            rootfs = m.group(0).rstrip("/*")
            share = Path(rootfs) / "usr" / "share" / "desktopeditors"
            return share if share.exists() else None


        def sync_tree(src, dst):
            # Mirror src → dst without --delete so the user cache can grow
            # with CEF runtime additions (Local Storage, IndexedDB shards,
            # dictionary caches) without us wiping them. The patched
            # index.html in the dst is preserved across re-syncs (we don't
            # recopy it; the patch step below handles it).
            if not dst.exists():
                shutil.copytree(src, dst, symlinks=True)
                return
            for src_root, _dirs, files in os.walk(src):
                rel = Path(src_root).relative_to(src)
                if rel == Path("."):
                    # Skip the patched index.html at the share root.
                    files = [f for f in files if f != "index.html"]
                dst_root = dst / rel
                dst_root.mkdir(parents=True, exist_ok=True)
                for name in files:
                    src_file = Path(src_root) / name
                    dst_file = dst_root / name
                    if not dst_file.exists() or src_file.stat().st_mtime > dst_file.stat().st_mtime:
                        shutil.copy2(src_file, dst_file, follow_symlinks=False)


        def patch_index_html(index_path, css):
            text = index_path.read_text(encoding="utf-8")
            if MARKER_BEGIN in text and MARKER_END in text:
                new_text = re.sub(
                    re.escape(MARKER_BEGIN) + r".*?" + re.escape(MARKER_END),
                    f"{MARKER_BEGIN}\n{css}\n        {MARKER_END}",
                    text,
                    count=1,
                    flags=re.DOTALL,
                )
            else:
                block = (
                    f'        <style type="text/css">\n        {MARKER_BEGIN}\n'
                    f"{css}\n        {MARKER_END}\n        </style>\n        "
                )
                new_text = text.replace("</head>", f"{block}</head>", 1)
            if new_text != text:
                index_path.write_text(new_text, encoding="utf-8")
                return True
            return False


        def kill_running():
            # CEF's parent process is the bwrap wrapper (comm: "bwrap" or
            # the wrapper name). The OnlyOffice DesktopEditors CEF binary
            # has comm ".onlyoffice-des" (15-char Linux limit, truncated
            # from ".onlyoffice-desktopeditors-wrapped"). Use pgrep -f to
            # match against full PRARGS, which still contains "onlyoffice"
            # substrings across the whole wrapper chain.
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
            # CEF flushes localStorage on SIGTERM; wait up to 5s.
            for _ in range(50):
                still = [pid for pid in pids if Path(f"/proc/{pid}").exists()]
                if not still:
                    return True
                time.sleep(0.1)
            return False


        home = Path(os.environ.get("HOME", str(Path.home())))
        cache_home = Path(os.environ.get("XDG_CACHE_HOME", home / ".cache"))
        config_home = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
        palette_path = cache_home / "DankMaterialShell" / "dms-colors.json"
        gtk_palette_path = config_home / "gtk-4.0" / "dank-colors.css"
        user_cache_share = cache_home / "onlyoffice-themes" / "desktopeditors"

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
        css = render_css(cache["colors"]["dark"], cache["colors"]["light"])

        share_dir = find_share_dir()
        if share_dir is None:
            sys.exit("Could not locate OnlyOffice FHS rootfs share dir")

        user_cache_share.parent.mkdir(parents=True, exist_ok=True)
        sync_tree(share_dir, user_cache_share)

        index_path = user_cache_share / "index.html"
        if not index_path.exists():
            sys.exit(f"index.html missing in {user_cache_share}")

        was_running = kill_running()
        if was_running:
            time.sleep(0.5)

        changed = patch_index_html(index_path, css)
        if changed or was_running:
            print(f"Synced OnlyOffice DMS theme (mode={mode}, changed={changed}, killed={was_running})")
        else:
            print(f"OnlyOffice DMS theme already up to date (mode={mode})")
      '';

      # Wrapper script that replaces $out/bin/onlyoffice-desktopeditors.
      # Runs the palette sync, then re-execs the original bwrap with the
      # --bind overlay prepended.
      #
      # `desktopeditors` here is the fhsenv-profile's wrapper symlink
      # (which is the actual bwrap script entry point). The nix store
      # path of the fhsenv-profile changes when onlyoffice-desktopeditors
      # is rebuilt; we discover it at runtime by walking from the package
      # binary the system installed.
      wrapperScript = pkgs.writeShellScriptBin "onlyoffice-desktopeditors-wrapped"
        ''
          set -euo pipefail

          # Run the palette sync (idempotent — re-runs are no-ops when the
          # cached index.html is already patched and unchanged).
          ${syncScript}/bin/sync-onlyoffice-dms-theme || true

          # Find the original bwrap launcher. After buildFHSEnv+extraInstall
          # the system's `desktopeditors` binary points at the fhsenv-profile
          # wrapper, which is the bwrap script. We resolve through the
          # installed package symlink chain.
          original=$(
              for cand in \\
                  /run/current-system/sw/bin/onlyoffice-desktopeditors \\
                  /run/current-system/sw/bin/desktopeditors; do
                  if [ -e "$cand" ]; then
                      readlink -f "$cand"
                      break
                  fi
              done
          )
          if [ -z "''${original:-}" ] || [ ! -x "$original" ]; then
              echo "onlyoffice-dms-theme: cannot locate original launcher" >&2
              exit 1
          fi

          exec "$original" \\
              --bind "$HOME/.cache/onlyoffice-themes/desktopeditors" \\
                       /usr/share/desktopeditors \\
              "$@"
        '';

      # The system-installed onlyoffice-desktopeditors package, with the
      # fhsenv-profile wrapper symlink replaced by our wrapper script.
      #
      # `overrideAttrs` on the buildFHSEnv result gives us a hook to
      # modify the post-install behavior — we append to the existing
      # extraInstallCommands, swapping the wrapper symlink in $out/bin.
      wrappedPackage = pkgs.onlyoffice-desktopeditors.overrideAttrs (old: {
        extraInstallCommands = (old.extraInstallCommands or "") + ''
          rm -f $out/bin/onlyoffice-desktopeditors
          ln -s ${wrapperScript}/bin/onlyoffice-desktopeditors-wrapped $out/bin/onlyoffice-desktopeditors
        '';
      });
    in
    {
      # The wrapped package replaces the unmodified onlyoffice-desktopeditors
      # in the system closure. Hosts that opt in to the office role
      # (config.nixos.modules.office) automatically pick this up; hosts that
      # don't have the office role are unaffected.
      #
      # We declare only `wrappedPackage` here, not the unwrapped
      # `pkgs.onlyoffice-desktopeditors`, because the override produces a
      # new store path with the same name — listing both would put two
      # ~400 MiB copies of OnlyOffice into the closure. The office role's
      # contribution (modules/packages/office/office.nix) also lists
      # `pkgs.onlyoffice-desktopeditors`; Nix deduplicates identical
      # derivations, so whichever one wins is the only one shipped. We
      # list `wrappedPackage` so the wrapper wins the dedup race.
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

      # Watch the DMS palette cache and our own user-cache share. DMS
      # updates dms-colors.json atomically (tmp+rename) so the path unit
      # has to watch the parent directory.
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