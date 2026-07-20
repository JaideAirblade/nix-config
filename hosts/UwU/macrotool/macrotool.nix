# Macrotool — Jaide's game macro/automation app (Tauri v2, Linux/Wayland).
#
# What this module does:
#   1. Adds the `jaide` user to the `input` and `uinput` groups so the app can
#      read raw evdev devices (/dev/input/event*) and create a virtual uinput
#      device for input injection. Without these groups the app would have to
#      run as root, which is not desirable.
#   2. Installs the runtime libraries the app links against at runtime:
#        - webkitgtk_4_1  (webview — Tauri uses WebKitGTK on Linux)
#        - gtk3, glib, libsoup_3
#        - libayatana-appindicator  (system tray icon; optional at runtime but
#          we ship it so the tray works out of the box)
#   3. Installs `grim` — the wlroots-native screen capture tool the app shells
#      out to for pixel-picker screenshots and pixel-trigger color checks.
#   4. Ships a udev rule that makes /dev/uinput group-owned by `uinput` with
#      mode 0660, so membership in the `uinput` group is enough to write to it
#      (no root needed).
#
# The app binary itself is NOT installed system-wide from here — it lives in
# ~/Projects/Projects/Macrotool and is built with the project's shell.nix /
# nix-shell. This module only provides the OS-level prerequisites. If you
# later want a proper system package for it, a derivation can be added to the
# project and referenced via an overlay; for now the dev build is fine.
{ pkgs, lib, config, ... }:

{
  # --- Group membership --------------------------------------------------------
  # `input`  → read /dev/input/event* (evdev capture for global hotkeys)
  # `uinput` → write /dev/uinput (virtual keyboard/mouse for input injection)
  users.users."jaide".extraGroups = [ "input" "uinput" ];

  # The `uinput` group is created implicitly by the udev rule below (or by
  # users.groups). Declare it explicitly so it exists even before the udev
  # rule fires, and so it shows up in `getent group`.
  users.groups."uinput" = {};

  # --- udev rule for /dev/uinput ----------------------------------------------
  # Default /dev/uinput is root:root mode 0660 (or 0600 on some kernels),
  # which means only root can write. This rule hands it to the `uinput` group
  # so any member (i.e. jaide) can create virtual devices without sudo.
  services.udev.extraRules = ''
    KERNEL=="uinput", GROUP="uinput", MODE="0660"
  '';

  # --- Runtime libraries + tools ----------------------------------------------
  environment.systemPackages = with pkgs; [
    # Tauri v2 webview + GUI stack (matched to the build-time nix-shell).
    webkitgtk_4_1
    gtk3
    glib
    libsoup_3
    # System tray support (Tauri's tray-icon feature dlopens this at runtime;
    # if missing the app falls back to no-tray mode, but we ship it so the
    # tray works.)
    libayatana-appindicator

    # Screen capture — the app shells out to `grim` for pixel picker + pixel
    # trigger screenshots. On wlroots compositors (Mango) this is the native
    # path. Slurp is also useful for interactive region selection.
    grim
    slurp
  ];
}