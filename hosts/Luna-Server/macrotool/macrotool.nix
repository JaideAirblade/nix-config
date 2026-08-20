# Macrotool (GTK 4 edition) — Jaide's game macro/automation app.
# Mirrored from hosts/UwU/macrotool/macrotool.nix for Luna-Server (2026-08-14).
#
# What this module does:
#   1. Adds the `jaide` user to the `input` and `uinput` groups so the app can
#      read raw evdev devices (/dev/input/event*) and create a virtual uinput
#      device for input injection.
#   2. Installs the macrotool-gtk4 package (binary + .desktop file) so it
#      appears in the app launcher and can be run by just typing `macrotool`.
#   3. Installs `grim` — the screen capture tool the app shells out to for
#      pixel-picker screenshots and pixel-trigger color checks.
#   4. Ships a udev rule that makes /dev/uinput group-owned by `uinput` with
#      mode 0660.
_:
{
  nixos.hosts."Luna-Server" =
    { pkgs, ... }:

    {
      # --- Group membership --------------------------------------------------------
      users.users."jaide".extraGroups = [ "input" "uinput" ];
      users.groups."uinput" = { };

      # --- udev rule for /dev/uinput ----------------------------------------------
      services.udev.extraRules = ''
        KERNEL=="uinput", GROUP="uinput", MODE="0660"
      '';

      # --- Package + runtime deps --------------------------------------------------
      environment.systemPackages = with pkgs; [
        # The app itself (binary + .desktop file)
        macrotool-gtk4

        # Screen capture — the app shells out to `grim` for pixel picker + pixel
        # trigger screenshots. On wlroots compositors (Mango) this is the native
        # path.
        grim
        slurp
      ];
    }
  ;
}
