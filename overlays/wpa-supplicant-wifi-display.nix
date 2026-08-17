# wpa_supplicant overlay: enable Wi-Fi Display (Miracast/WFD) support.
#
# nixpkgs builds wpa_supplicant with CONFIG_P2P=y but WITHOUT
# CONFIG_WIFI_DISPLAY=y. Without WFD support, wpa_supplicant doesn't
# process Wi-Fi Display Information Elements in P2P peer beacons, and
# NetworkManager's WifiP2P device never relays peers to applications
# like gnome-network-displays — so no Miracast devices appear even
# though wpa_supplicant finds them (visible as P2P-DEVICE-FOUND in
# the journal with wfd_dev_info=0x... fields).
#
# This overlay appends CONFIG_WIFI_DISPLAY=y to the .config file
# before building. See:
#   https://discourse.nixos.org/t/how-can-i-use-miracast-in-nixos/29405
#   https://w1.fi/wpa_supplicant/devel/wfd.html
final: prev: {
  wpa_supplicant = prev.wpa_supplicant.overrideAttrs (old: {
    extraConfig = (old.extraConfig or "") + ''
      CONFIG_WIFI_DISPLAY=y
    '';
  });
}