# DankMaterialShell — desktop shell + greeter.
#
# Loaded as NixOS modules directly from the official flake so we don't
# need home-manager. Two modules are imported:
#   - nixosModules.dank-material-shell : the shell itself (bar, notifs,
#     launcher, lock screen, polkit agent, ...) as a systemd user service
#     bound to graphical-session.target.
#   - nixosModules.greeter : DankGreeter, a Wayland greeter running under
#     greetd that launches the compositor on login. Mango is in its
#     supported compositor enum.
#
# Per https://danklinux.com/docs/dankgreeter/nixos-flake we set
# `compositor.name = "mango"`. The greeter reads the user's DMS
# settings/theme for a consistent login look.
{ inputs, ... }:

{
  imports = [
    inputs.dms.nixosModules.dank-material-shell
    inputs.dms.nixosModules.greeter
  ];

  programs.dank-material-shell = {
    enable = true;
    systemd.enable = true;

    # Optional feature toggles (all default true; spell them out so we
    # notice when the upstream defaults change).
    enableSystemMonitoring = true;
    enableVPN = true;
    enableDynamicTheming = true;
    enableAudioWavelength = true;
    enableCalendarEvents = true;

    greeter = {
      enable = true;
      compositor.name = "mango";
      # Sync the greeter's DMS theme with jaide's user theme.
      configHome = "/home/jaide";
    };
  };
}