# GNOME Network Displays — Miracast screen casting to wireless displays.
#
# gnome-network-displays streams the desktop to Miracast-capable TVs/projectors
# using the Wi-Fi Display (WFD) protocol over WiFi Direct (P2P).
#
# Requirements (all verified working on TSBW-W01800 as of 2026-08-17):
#   - wpa_supplicant with P2P support (CONFIG_P2P) ✓
#   - NetworkManager managing the WiFi device ✓ (wifi.backend=wpa_supplicant)
#   - p2p-dev-wlp2s0 WiFi P2P device ✓
#   - PipeWire for audio/screen capture ✓
#   - xdg-desktop-portal-wlr for screencast portal (Mango implements
#     zwlr_screencopy_manager_v1) ✓
#   - A picker program (wofi) for the portal's output/source chooser dialog
#
# The xdg-desktop-portal-wlr backend needs a menu program on PATH to show the
# "select which monitor to share" dialog. Without it, SelectSources() fails
# silently and gnome-network-displays can't start a screencast session.
# The portal auto-detects choosers in order: slurp, wmenu, wofi, rofi, bemenu,
# mew, fuzzel. We install wofi and set chooser_type=default so it's found
# automatically.
#
# NOTE: gnome-network-displays does NOT support AirPlay/Apple TV — only
# Miracast. For AirPlay sending, see the `doubletake` project
# (not packaged in nixpkgs).
{
  nixos.hosts."TSBW-W01800" =
    { pkgs, lib, ... }:

    {
      environment.systemPackages = with pkgs; [
        gnome-network-displays
        wofi # output chooser for xdg-desktop-portal-wlr screencast
      ];

      # Enable the wlroots portal backend for ScreenCast (screencast interface).
      # gnome-network-displays calls org.freedesktop.portal.ScreenCast.SelectSources
      # to obtain a PipeWire stream of the desktop. Without xdg.portal.wlr.enable
      # the backend isn't registered, so SelectSources() fails silently — no
      # video sinks appear and no chooser popup opens.
      xdg.portal.wlr = {
        enable = true;
        settings.screencast.chooser_type = "default";
      };

      # The NixOS xdg-desktop-portal-wlr module sets a minimal PATH (coreutils,
      # findutils, etc.) that does NOT include /run/current-system/sw/bin, so
      # the chooser programs (wofi, slurp, etc.) installed via
      # environment.systemPackages are invisible to the portal service.
      # When SelectSources() runs, the portal tries each chooser in turn and
      # gets "command not found" for all of them, then returns "canceled".
      # Fix: force the PATH to include wofi alongside the module's defaults.
      systemd.user.services.xdg-desktop-portal-wlr.environment = {
        PATH = lib.mkForce (lib.makeBinPath [
          pkgs.wofi
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.systemd
        ]);
      };

      # NixOS upstream adds a udev rule that restarts wpa_supplicant whenever
      # a wlan device is added or removed:
      #   ACTION=="add|remove", SUBSYSTEM=="net", ENV{DEVTYPE}=="wlan",
      #   RUN+="systemctl try-restart wpa_supplicant.service"
      # This rule is only generated when networking.wireless.interfaces is
      # empty (the default). When NM creates a P2P virtual interface
      # (p2p-wlp2s0-N) during Miracast discovery, the rule fires and restarts
      # wpa_supplicant, wiping the P2P peer list and disrupting the WFD
      # session.
      # See: https://discourse.nixos.org/t/how-can-i-use-miracast-in-nixos/29405
      #      https://github.com/NixOS/nixpkgs/commit/7544590
      # Fix: set networking.wireless.interfaces to ["wlp2s0"] so the upstream
      # module skips the udev rule. NM still controls wpa_supplicant via D-Bus
      # (dbusControlled=true), so the per-interface service name doesn't
      # matter — NM talks to fi.w1.wpa_supplicant1 on the system bus.
      networking.wireless.interfaces = [ "wlp2s0" ];

      # Firewall: gnome-network-displays needs RTSP (7236/7250 TCP) and
      # mDNS discovery (5353 UDP) for the WFD session. The P2P group
      # interface (p2p-wl+) should be trusted to allow the TV to connect
      # back to the source.
      networking.firewall.trustedInterfaces = [ "p2p-wl+" ];
      networking.firewall.allowedTCPPorts = [ 7236 7250 ];
      networking.firewall.allowedUDPPorts = [ 7236 5353 ];
    }
  ;
}