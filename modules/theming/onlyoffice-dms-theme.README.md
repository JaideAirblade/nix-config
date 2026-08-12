# onlyoffice-dms-theme

Theme OnlyOffice Desktop Editors with the live DankMaterialShell palette.

## What it does

OnlyOffice's chrome (sidebars, toolbars, file lists, tabs) is rendered by a
Chromium Embedded Framework process whose entire UI theme lives in
`/usr/share/desktopeditors/index.html` — ~200 KB of CSS variables keyed off
`theme-{dark,night,white,contrast,gray,classic}` classes on `<html>`. We
override those variables with DMS-derived Material Design 3 colors so
OnlyOffice matches the rest of the desktop whenever DMS changes wallpaper or
flips light/dark.

## How it works

OnlyOffice is shipped as a CEF binary inside a `buildFHSEnv` wrapper. The
fhsenv-profile launcher invokes `bwrap`, which mounts the FHS rootfs read-only
into a private namespace. CEF reads `index.html` from `/usr/share/desktopeditors/`
— the same path every launch.

The hook is `bwrap`'s `--bind` semantics: later mounts shadow earlier ones. We
add a second, writable `--bind` of `~/.cache/onlyoffice-themes/desktopeditors`
over the read-only `/usr/share/desktopeditors` mount, so CEF reads our
patched copy.

```
$ bwrap ... --ro-bind <fhsenv>/usr/share/desktopeditors /usr/share/desktopeditors \
           --bind ~/.cache/onlyoffice-themes/desktopeditors /usr/share/desktopeditors \
           ... <cef binary>
```

The cache tree is a mirror of the FHS rootfs share, with `index.html` patched
to include a `<style>` block overriding OO's CSS variables. A systemd user
service regenerates the cache + CSS whenever DMS updates `dms-colors.json`.

## What gets colored

Mapped from Material Design 3 (DMS palette) to OnlyOffice CSS variables:

| MD3 token | OO variables |
|---|---|
| `surface` | `--background-normal`, `--background-tabbar` |
| `surface_container` | `--background-action-panel`, `--background-icon-normal` |
| `surface_container_high` | `--highlight-button-hover`, `--background-scroll-thumb` |
| `surface_container_highest` | `--highlight-button-pressed` |
| `primary` | `--background-accent-button`, `--highlight-text-select`, `--highlight-toolbar-tab-underline-document` |
| `primary_container` | `--highlight-accent-button-hover` |
| `on_primary` | `--text-inverse` |
| `on_surface` | `--text-normal`, `--icon-normal` |
| `on_surface_variant` | `--text-secondary`, `--text-tertiary` |
| `outline` | `--border-regular-control` |
| `outline_variant` | `--border-divider`, `--border-tabbar`, `--border-sidebar` |
| `error` | `--border-error`, `--text-negative` |
| `tertiary` | `--icon-success` |

Both `dark` and `light` palettes are baked into the override block, so the
user can pick `theme-dark`, `theme-night`, etc. in OO's Settings → Interface
theme and still see DMS colors.

## Caveats

- **Running OnlyOffice is killed on palette change.** CEF holds the
  `index.html` file handle open, so the new colors only land on next launch.
  CEF flushes localStorage (open documents, recent files) on SIGTERM, so the
  user loses nothing. The watcher does NOT kill OnlyOffice automatically —
  the user has to close it themselves; the next launch picks up new colors.
  (This is a deliberate trade-off vs. silently killing the app while the
  user is editing.)
- **Two copies of OnlyOffice ship (~800 MiB instead of ~400 MiB).** The
  `office` role installs `pkgs.onlyoffice-desktopeditors` (unwrapped); this
  module installs a `.overrideAttrs` variant (wrapped). Both have different
  store paths and end up in the closure. On three hosts = ~1.2 GiB extra
  disk. Deduping cleanly requires either a package passthrough attr or
  merging the two modules; neither is justified for a one-time install cost.
- **Mode detection matches Legcord/Readest heuristics:** pick the DMS
  palette variant whose `background` color matches the GTK window-bg color.
  This naturally follows DMS light/dark mode flips via gsettings. Doesn't
  support a per-app override (onlyOffice's interface theme picker is
  independent — see "What gets colored" above).