# The installed system — this is what nixos-install writes to disk.
# Minimal standalone config: one `ap` user with a yescrypt hash, WiFi AP
# sharing any wired LAN connection via NAT (using linux-wifi-hotspot/create_ap).
# No SSH — console-only.
{ lib, pkgs, ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "LaptopAP";

  # Minimal packages for a headless AP laptop.
  environment.systemPackages = with pkgs; [
    vim
    htop
    iw
    iproute2
  ];

  # User `ap` with a baked-in yescrypt hash.
  # Generate your own with: echo -n 'yourpassword' | mkpasswd -m yescrypt -s
  users.users.ap = {
    isNormalUser = true;
    description = "Access Point";
    extraGroups = [ "wheel" ];
    hashedPassword = "$y$j9T$VoNZPXtG1RmMD0weDHtz2/$AfWk1/xII92/hIDwvxcSerYuH7dJ0CeBDVBCk22TXEB";
  };

  users.users.root.hashedPassword = "!";

  # Rename wireless and wired interfaces to predictable names so create_ap
  # can reference them regardless of hardware.
  # NOTE: udev renames can race with driver loading. create_ap uses
  # auto-detection as a fallback (see the ExecStartPre wrapper below).
  services.udev.extraRules = ''
    # Rename any wireless interface to wlan0.
    SUBSYSTEM=="net", ACTION=="add", KERNEL=="wlan*|wlp*", NAME="wlan0"
    # Rename any wired (Ethernet) interface to eth0.
    SUBSYSTEM=="net", ACTION=="add", KERNEL=="eth*|en*", NAME="eth0"
  '';

  # Use NetworkManager for the wired interface (eth0) — it handles DHCP,
  # DNS, and carrier detection. create_ap uses wlan0 for the hotspot.
  networking.networkmanager.enable = true;
  networking.useDHCP = false;

  # Let NetworkManager manage eth0 but NOT wlan0 (create_ap owns it).
  # Also exclude any wlp* interfaces in case udev rename hasn't happened yet.
  networking.networkmanager.unmanaged = [ "wlan0" "wlp*" ];

  # Firewall enabled — create_ap handles NAT rules itself.
  networking.firewall.enable = true;

  # WiFi hotspot using create_ap (linux-wifi-hotspot).
  # Shares the wired connection (eth0) over WiFi (wlan0) via NAT.
  # create_ap handles hostapd, dnsmasq, NAT, and firewall rules internally.
  services.create_ap = {
    enable = true;
    settings = {
      # These can be overridden by the wrapper script at runtime.
      INTERNET_IFACE = "eth0";
      WIFI_IFACE = "wlan0";
      SSID = "TSBW-Hotspot";
      PASSPHRASE = "weissichnicht";
      # Use the interface directly, no virtual interface creation.
      NO_VIRT = 1;
      # WPA2 for broad client compatibility.
      WPA_VERSION = 2;
      # 2.4GHz band, default channel (auto-selects least congested).
      FREQ_BAND = "2.4";
      # Use the default gateway subnet for the hotspot LAN.
      GATEWAY = "192.168.12.1";
      # Use the gateway as DNS relay (forwards to upstream DNS from DHCP).
      DHCP_DNS = "gateway";
      # NAT sharing method.
      SHARE_METHOD = "nat";
      # 802.11n support for better throughput.
      IEEE80211N = 1;
      HT_CAPAB = "[HT40+]";
    };
  };

  # Make create_ap robust:
  # 1. Wait for the WiFi interface to appear (driver may load late).
  # 2. If udev rename to wlan0 didn't happen, find the real wireless iface.
  # 3. If eth0 rename didn't happen, find the real wired iface.
  # 4. Kill any NetworkManager residual holding the WiFi interface.
  # 5. Generate a runtime config with the detected interface names.
  systemd.services.create_ap = {
    after = [ "network.target" "NetworkManager.service" ];
    wants = [ "network.target" ];
    # Override the ExecStart to use a wrapper that detects interfaces.
    serviceConfig = {
      ExecStartPre = [
        # Wait for ANY wireless interface to appear, then ensure it's named wlan0.
        "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 60); do iw dev 2>/dev/null | grep -q Interface && break; sleep 1; done'"
        # If wlan0 doesn't exist but a wlp* does, rename it.
        "${pkgs.bash}/bin/bash -c '[ -e /sys/class/net/wlan0 ] || { w=\$(ls /sys/class/net/ | grep -E \"^wlp\" | head -1); [ -n \"\$w\" ] && ${pkgs.iproute2}/bin/ip link set \$w name wlan0; }'"
        # If eth0 doesn't exist but an en* does, rename it.
        "${pkgs.bash}/bin/bash -c '[ -e /sys/class/net/eth0 ] || { e=\$(ls /sys/class/net/ | grep -E \"^enp|^eno|^ens\" | head -1); [ -n \"\$e\" ] && ${pkgs.iproute2}/bin/ip link set \$e name eth0; }'"
        # Kill NetworkManager if it's still holding wlan0.
        "${pkgs.procps}/bin/pkill -f 'NetworkManager.*wlan0' 2>/dev/null || true"
        # Bring wlan0 down then up to clear residual state.
        "${pkgs.iproute2}/bin/ip link set wlan0 down 2>/dev/null || true"
        "${pkgs.iproute2}/bin/ip link set wlan0 up 2>/dev/null || true"
      ];
    };
    path = with pkgs; [ iw iproute2 procps bash ];
  };

  # Keep running when the laptop lid is closed.
  services.logind = {
    lidSwitch = "ignore";
    lidSwitchDocked = "ignore";
    lidSwitchExternalPower = "ignore";
  };

  # Auto-update monthly.
  system.autoUpgrade = {
    enable = true;
    dates = "monthly";
    allowReboot = true;
  };

  # Garbage collection.
  nix.gc = {
    automatic = true;
    dates = "monthly";
    options = "--delete-older-than 30d";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "26.05";
}
