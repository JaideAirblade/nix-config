# DankMaterialShell — desktop shell + greeter.
#
# Loaded as NixOS modules directly from the official flakes so we don't
# need home-manager. Three modules are imported:
#   - nixosModules.dank-material-shell : the shell itself (bar, notifs,
#     launcher, lock screen, polkit agent, ...) as a systemd user service
#     bound to graphical-session.target.
#   - nixosModules.default (dank-greeter) : DankGreeter, a Wayland greeter
#     running under greetd that launches the compositor on login.
#     As of July 2026 the greeter was split into its own flake
#     (github:AvengeMedia/dank-greeter). It was previously
#     nixosModules.greeter inside the DMS flake.
#
# Defaults here are deliberately written with lib.mkDefault so a host can
# override them (e.g. TSBW-W01800 sets compositor.name = "niri" and pulls in
# DankCalendar). UwU uses the defaults (mango, calendar events via khal).
{ inputs, lib, ... }:

{
  imports = [
    inputs.dms.nixosModules.dank-material-shell
    inputs.dank-greeter.nixosModules.default
  ];

  # DMS ships its own polkit authentication agent (enabled by default;
  # setting DMS_DISABLE_POLKIT=1 would disable it). We explicitly enable
  # the polkit daemon here so the agent has something to talk to. No other
  # polkit agent (polkit_gnome, polkit_kde, ...) is enabled on this system,
  # so there is no conflict — DMS is the sole agent.
  security.polkit.enable = true;

  programs.dank-material-shell = {
    enable = true;
    systemd.enable = true;

    # Optional feature toggles (all default true; spell them out so we
    # notice when the upstream defaults change). mkDefault so a host can
    # flip one without re-listing the rest.
    enableSystemMonitoring = lib.mkDefault true;
    enableVPN = lib.mkDefault true;
    enableDynamicTheming = lib.mkDefault true;
    enableAudioWavelength = lib.mkDefault true;
    enableCalendarEvents = lib.mkDefault true;
  };

  # DankGreeter — the greeter is now configured via programs.dms-greeter
  # (from the dank-greeter flake), not programs.dank-material-shell.greeter.
  programs.dms-greeter = {
    enable = true;
    # Default compositor. TSBW-W01800 overrides this to "niri".
    compositor.name = lib.mkDefault "mango";
    # Sync the greeter's DMS theme with jaide's user theme.
    configHome = "/home/jaide";
  };
}