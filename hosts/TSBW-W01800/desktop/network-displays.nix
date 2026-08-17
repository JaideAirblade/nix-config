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
    { pkgs, ... }:

    {
      environment.systemPackages = with pkgs; [
        gnome-network-displays
        wofi # output chooser for xdg-desktop-portal-wlr screencast
      ];

      # Configure the wlroots portal backend.
      # chooser_type=default lets the portal auto-detect wofi on PATH.
      # If multiple monitors are connected, wofi pops up to let you pick
      # which one to share. For a single-monitor setup it's a no-op.
      xdg.portal.wlr.settings = {
        screencast = {
          chooser_type = "default";
        };
      };
    }
  ;
}