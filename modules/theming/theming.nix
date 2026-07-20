# System-wide theme packages and the env vars that wire them up.
#
# - adw-gtk3: GTK3 port of libadwaita, so GTK3 apps match the libadwaita
#   look used by GTK4/DMS. The user picks `adw-gtk3` or `adw-gtk3-dark`
#   via their own gsettings/gtk config (kept writable — no home-manager).
# - qogir-theme + qogir-icon-theme: the GTK widget theme + icon theme the
#   user's ~/.config/gtk-3.0/settings.ini references (gtk-icon-theme-name=Qogir,
#   gtk-cursor-theme-name=Qogir). These must land in
#   /run/current-system/sw/share/{themes,icons} for GTK to find them;
#   otherwise apps silently fall back to defaults. The icon package also
#   ships the Qogir cursor theme (cursors live under icons/ in nixpkgs).
#   (The widget theme switched to adw-gtk3-dark because DMS's matugen
#   CSS overrides libadwaita variable names — Qogir's hardcoded light
#   styling was bleeding through in dark mode.)
# - kdePackages.qt6ct: Qt6 Configuration Tool. We use the vanilla nixpkgs
#   build (no KDE-patches variant exists in nixpkgs; see
#   https://github.com/NixOS/nixpkgs/issues/489021 for the KDE-app theming
#   gap). QT_QPA_PLATFORMTHEME=qt6ct makes Qt6 apps load the qt6ct plugin.
#   The user picks the actual Qt theme/colours via the `qt6ct` GUI or
#   ~/.config/qt6ct/qt6ct.conf (kept writable).
# - programs.dconf: the dconf daemon + gsettings backend. DMS sets
#   `syncModeWithPortal = true`, which reads the xdg-desktop-portal
#   color-scheme preference; the portal in turn reads
#   org.freedesktop.appearance.color-scheme via gsettings. Without the
#   dconf daemon + that schema, the portal has no preference to report,
#   so DMS can't pick up a system-wide dark-mode hint. Enabling dconf
#   lets the user run `gsettings set org.freedesktop.appearance
#   color-scheme 1` (prefer-dark) once and have DMS honour it.
{ pkgs, ... }:

{
  # dconf daemon + gsettings backend so xdg-desktop-portal can read the
  # user's color-scheme preference (org.freedesktop.appearance).
  programs.dconf.enable = true;

  environment.systemPackages = with pkgs; [
    adw-gtk3
    qogir-theme
    qogir-icon-theme
    kdePackages.qt6ct

    # Extra icon themes the user can pick from (set via gtk-icon-theme-name
    # in ~/.config/gtk-3.0/settings.ini, or the DE's appearance settings).
    # These install side-by-side with qogir-icon-theme; nothing forces them
    # active — the user chooses in their own dotfiles.
    fluent-icon-theme
    papirus-icon-theme
    vimix-icon-theme    # Material Design icon theme (carried over from work config)

    # Cursor theme. Same deal — installed but not forced; the user points
    # gtk-cursor-theme-name (or the compositor's cursor setting) at it.
    bibata-cursors
  ];

  # Tell Qt6 apps to use the qt6ct platform theme plugin so they honour
  # the user's qt6ct.conf. (Qt5 apps read the same var and use qt5ct if
  # installed; we don't force-install qt5ct here — add libsForQt5.qt5ct
  # if a Qt5 app needs it.)
  environment.variables.QT_QPA_PLATFORMTHEME = "qt6ct";

  # Nix-wrapped Qt apps (prismlauncher, etc.) get QT_PLUGIN_PATH set to
  # ONLY their own Qt dependency plugin dirs by wrap-qt6-apps-hook. That
  # list does NOT include qt6ct (it's a systemPackage, not a buildInput
  # of every Qt app), so the qt6ct platform theme plugin is invisible to
  # them and QT_QPA_PLATFORMTHEME=qt6ct silently falls back to the default
  # style. Adding qt6ct's plugin dir here makes it discoverable by every
  # Qt app — wrapped or not — because the wrapper uses --prefix (it
  # prepends its own paths but preserves the existing value at the end,
  # where Qt still searches it).
  environment.variables.QT_PLUGIN_PATH = "${pkgs.kdePackages.qt6ct}/lib/qt-6/plugins";

  # Electron/Chromium apps (Discord+Equicord, Heroic, 1Password-GUI, ...)
  # default to XWayland on a Wayland-only session. With OZONE_WL they run
  # native Wayland — better HiDPI scaling, sane screen-share, and fewer
  # XWayland edge cases. Set session-wide so it covers graphical-session
  # user services and interactive shells alike.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}