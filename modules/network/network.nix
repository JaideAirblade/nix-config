# Networking.
#
# Hostname is intentionally NOT set here — each host sets its own in
# hosts/<name>/network/network.nix so the shared module stays portable.
#
# Privacy: NetworkManager randomizes MAC addresses on all connections
# (ethernet + wifi) and the hostname broadcast via DHCP is randomized
# on every boot. The static hostname (e.g. "UwU") is kept for
# nixos-rebuild --flake .#<hostname> and local shell prompts.
{ inputs, ... }:
{
  nixos.modules.common =
    { pkgs, ... }:

    {
      networking.networkmanager.enable = true;

      # Capability-bearing network diagnostics are executable only by this
      # dedicated group. This grants jaide access without adding her to root.
      users.groups.net-report = { };
      users.users.jaide.extraGroups = [ "net-report" ];

      # nm-connection-editor — standalone GUI for editing NM connection profiles.
      # This is the full configuration tool (static IP, DNS, routes, MAC cloning,
      # 802.1x, etc.), NOT the nm-applet tray icon. Launch it from the app menu
      # or run `nm-connection-editor` from the terminal.
      # net-report — full network status report (LLDP, routes, DNS, firewall,
      # WiFi, sockets, VPN, public IP, traceroute, etc.)
      # Run `net-report` for everything, `net-report --section lldp` for one section,
      # `net-report --json` for machine-readable output.
      environment.systemPackages = with pkgs; [
        networkmanagerapplet
        net-report
        iw # for wifi-scan section (monitor mode setup)
      ];

      # Capabilities for net-report wifi-scan section (deauth + probe sniffing)
      # This allows the wifi-scan section to run without sudo by granting
      # cap_net_admin (create monitor interfaces, set channels) and
      # cap_net_raw (capture/inject raw 802.11 frames) to the tools it uses.
      # Only enable if you want sudo-less wifi-scan (it does increase attack surface).
      security.wrappers = {
        # `iw` can create the monitor netdev, but only `ip` can set its IFF_UP
        # flag. Keep this capability restricted to the dedicated net-report
        # group just like the other active WiFi diagnostics.
        net-report-ip = {
          source = "${pkgs.iproute2}/bin/ip";
          owner = "root";
          group = "net-report";
          permissions = "u+rx,g+rx";
          capabilities = "cap_net_admin+eip";
        };
        net-report-iw = {
          source = "${pkgs.iw}/bin/iw";
          owner = "root";
          group = "net-report";
          permissions = "u+rx,g+rx";
          capabilities = "cap_net_admin,cap_net_raw+eip";
        };
        net-report-tcpdump = {
          source = "${pkgs.tcpdump}/bin/tcpdump";
          owner = "root";
          group = "net-report";
          permissions = "u+rx,g+rx";
          capabilities = "cap_net_raw+eip";
        };
        net-report-aireplay = {
          source = "${pkgs.aircrack-ng}/bin/aireplay-ng";
          owner = "root";
          group = "net-report";
          permissions = "u+rx,g+rx";
          capabilities = "cap_net_admin,cap_net_raw+eip";
        };
      };

      services.ivpn.enable = true;

      # Pull ivpn/ivpn-service/ivpn-ui from the pinned nixpkgs-ivpn input
      # (PR #542306: 3.15.6 -> 3.15.13) ahead of the merge. Drop once landed.
      nixpkgs.overlays = [ (import ./ivpn.overlay.nix { inherit inputs; }) ];

      # --- MAC address randomization -------------------------------------------
      # NetworkManager generates a random MAC per connection (not per boot —
      # each saved network gets its own persistent random MAC, so you keep
      # the same "fake" MAC on your home wifi but a different one on coffee
      # shop wifi). This is more practical than a fully random MAC on every
      # boot because some routers whitelist MACs or assign fixed IPs.
      #
      # NixOS's networking.networkmanager.settings puts keys under [ethernet]
      # and [wifi] sections, but NetworkManager expects cloned-mac-address
      # under the [connection] section. We use an explicit config file via
      # environment.etc to get the section placement right.
      #
      # The [connection] section sets default values for all connection
      # profiles. ethernet.cloned-mac-address and wifi.cloned-mac-address
      # are per-connection properties that can be defaulted here.
      environment.etc."NetworkManager/conf.d/30-mac-randomization.conf".text = ''
        [connection]
        ethernet.cloned-mac-address=random
        wifi.cloned-mac-address=random
      '';

      # wifi.scan-rand-mac-address is a [device] section property. The NixOS
      # networking.networkmanager.settings option puts it under [wifi], which
      # NM logs as "unknown key". Use environment.etc to place it correctly.
      environment.etc."NetworkManager/conf.d/31-wifi-scan-random.conf".text = ''
        [device]
        wifi.scan-rand-mac-address=yes
      '';

      # --- Random hostname broadcast via DHCP ----------------------------------
      # The STATIC hostname (networking.hostName, e.g. "UwU") is used by
      # nixos-rebuild --flake .#UwU and shell prompts — it must not change.
      # When a static hostname is set, `hostnamectl set-hostname --transient`
      # is silently ignored. Instead, we set a random DHCP hostname via:
      #   1. A boot-time systemd service that sets it on all EXISTING
      #      connection profiles before NetworkManager starts.
      #   2. A NetworkManager dispatcher script that sets it on NEW
      #      connections (e.g. joining a new wifi network for the first time).
      #
      # The hostname mimics formats that real devices use on home networks
      # (Windows: DESKTOP-XXXXXX, Android: android-xxxx, Mac: MacBook-xxxx,
      # generic: PC-xxxx, Laptop-xxxx). A random prefix is picked from the
      # list and combined with a random alphanumeric suffix, so the result
      # looks like a normal device that just joined the network.

      # Shared script: generates a random realistic-looking hostname.
      # Used by both the boot service and the dispatcher script.
      environment.etc."NetworkManager/generate-random-hostname.sh" = {
        mode = "0755";
        text = ''
          #!/bin/sh
          # Generate a random hostname that mimics real device names.
          # Output: a single line on stdout, suitable for dhcp-hostname.
          #
          # Each entry is "prefix|suffix_type" where suffix_type controls
          # the random suffix format:
          #   hex7  — 7 uppercase hex chars (Windows DESKTOP-XXXXXXX)
          #   hex6  — 6 uppercase hex chars (generic PC/laptop)
          #   hex8  — 8 lowercase hex chars (Android)
          #   dec2  — 2-digit decimal (Apple devices)
          #   dec4  — 4-digit decimal (TVs, streaming devices)
          #   mac   — MAC-style hex (printers: XX-XX-XX)
          #   none  — no suffix (simple names)

          entries="
          DESKTOP-|hex7
          LAPTOP-|hex6
          android-|hex8
          android-dhcp-|dec1
          MacBook|dec2
          MacBookPro|dec2
          MacBookAir|dec2
          iPad|dec2
          iPhone|dec2
          PC-|hex6
          ThinkPad-|hex6
          Pavilion-|hex6
          Inspiron-|hex6
          XPS-|hex6
          ZenBook-|hex6
          Surface-|hex6
          Chromebook-|hex6
          GALAXY-|hex6
          Galaxy-|dec4
          Pixel-|dec1
          Vostro-|hex6
          Presario-|hex6
          Satellite-|hex6
          IdeaPad-|hex6
          Yoga-|hex6
          Envy-|hex6
          Spectre-|hex6
          ROG-|hex6
          TUF-|hex6
          Omen-|hex6
          Victus-|hex6
          Nitro-|hex6
          Predator-|hex6
          MSI-|hex6
          HP-|hex6
          Epson-|mac
          EPSON-|mac
          Canon-|mac
          CANON-|mac
          Brother-|mac
          HP-Print-|mac
          Roku-|dec4
          AppleTV|dec2
          Apple-TV|dec2
          AppleTV|dec2
          FireTV-|dec4
          Fire-TV-|dec4
          Chromecast|dec2
          SmartTV-|hex6
          Samsung-TV|dec4
          BRAVIA|dec4
          TCL-TV|dec4
          Hisense-TV|dec4
          Synology-|hex6
          NAS-|hex6
          Kindle-|hex6
          Echo|dec2
          HomePod|dec2
          "

          # Count and pick from non-empty lines only
          count=$(echo "$entries" | grep -c .)
          n=$(head -c1 /dev/urandom | od -An -tu1 | tr -d ' \n')
          idx=$(( n % count + 1 ))
          entry=$(echo "$entries" | grep . | sed -n "''${idx}p")

          # Split on | into prefix and suffix_type
          prefix=$(echo "$entry" | cut -d'|' -f1)
          suffix_type=$(echo "$entry" | cut -d'|' -f2)

          # Generate the appropriate suffix
          case "$suffix_type" in
            hex7)
              suffix=$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n' | tr 'a-f' 'A-F' | cut -c1-7)
              ;;
            hex6)
              suffix=$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n' | tr 'a-f' 'A-F' | cut -c1-6)
              ;;
            hex8)
              suffix=$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8)
              ;;
            dec2)
              n=$(head -c1 /dev/urandom | od -An -tu1 | tr -d ' \n')
              suffix=$(printf '%02d' $(( n % 99 + 1 )))
              ;;
            dec4)
              n=$(head -c2 /dev/urandom | od -An -tu2 | tr -d ' \n')
              suffix=$(printf '%04d' $(( n % 9999 + 1 )))
              ;;
            dec1)
              n=$(head -c1 /dev/urandom | od -An -tu1 | tr -d ' \n')
              suffix=$(( n % 14 + 1 ))
              ;;
            mac)
              suffix=$(head -c3 /dev/urandom | od -An -tx1 | tr -d ' \n' | sed 's/\(..\)/\1-/g; s/-$//')
              ;;
            none)
              suffix=""
              ;;
            *)
              suffix=""
              ;;
          esac

          echo "''${prefix}''${suffix}"
        '';
      };

      # Boot-time service: set a random DHCP hostname on existing profiles.
      # nmcli requires NetworkManager's D-Bus service, so run after NM starts;
      # the values apply on the next activation/renewal. The dispatcher below
      # keeps rotating them on subsequent connections.
      systemd.services.random-dhcp-hostname = {
        description = "Set random DHCP hostname in NM connection profiles";
        after = [ "NetworkManager.service" ];
        wants = [ "NetworkManager.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.networkmanager ];
        script = ''
          # Generate a DIFFERENT random hostname for each connection profile,
          # so wifi and ethernet (and dock ethernet) all broadcast different
          # names. This prevents cross-correlation between adapters.
          for uuid in $(nmcli -g UUID connection show); do
            rand=$(/etc/NetworkManager/generate-random-hostname.sh)
            nmcli connection modify "$uuid" \
              ipv4.dhcp-hostname "$rand" \
              ipv6.dhcp-hostname "$rand" \
              2>/dev/null && echo "Set DHCP hostname to $rand for connection $uuid" \
              || echo "Failed to set DHCP hostname for $uuid (may not have DHCP)"
          done
        '';
        serviceConfig = {
          Type = "oneshot";
        };
      };

      # Dispatcher script: sets a new random DHCP hostname on every connection-up.
      # This fires when you connect to ANY network (new or existing), giving you
      # a fresh random hostname each time. Combined with the boot service, this
      # means:
      #   - Boot → each existing profile gets a new random hostname
      #   - Reconnect to same network → new random hostname
      #   - Join new network → new random hostname
      #
      # The hostname is set AFTER the connection is up, so it takes effect on
      # the NEXT DHCP renewal (usually within the lease period — a few hours).
      # For immediate effect, disconnect and reconnect after the script runs.
      environment.etc."NetworkManager/dispatcher.d/10-random-hostname.sh" = {
        mode = "0755";
        text = ''
          #!/bin/sh
          # Sets a fresh random DHCP hostname on every connection-up event.
          # $1 = interface, $2 = action
          [ "$2" = "up" ] || exit 0
          export PATH="/run/current-system/sw/bin:$PATH"

          rand=$(/etc/NetworkManager/generate-random-hostname.sh)
          nmcli connection modify "$CONNECTION_ID" \
            ipv4.dhcp-hostname "$rand" \
            ipv6.dhcp-hostname "$rand" \
            2>/dev/null && echo "Set DHCP hostname to $rand for $CONNECTION_ID" \
            || true
        '';
      };

      # --- WiFi latency optimization -------------------------------------------
      # Disable WiFi power saving on all connections. Power saving causes the
      # radio to sleep between beacons (every 100ms), adding up to 100ms of
      # wake-up delay to each incoming packet. On a desktop plugged into wall
      # power, the battery savings are irrelevant — latency matters more.
      #
      # We set this two ways for belt-and-suspenders:
      #   1. NM default config (applies to all current + future connections)
      #   2. Dispatcher script (enforces it on every connection-up event)
      environment.etc."NetworkManager/conf.d/40-wifi-powersave-off.conf".text = ''
        [connection]
        # 1 = enabled (default), 2 = disabled
        wifi.powersave = 2
      '';

      # Dispatcher: force power_save off on every WiFi interface up event.
      # This catches cases where the NM config default doesn't apply (e.g.
      # existing connection profiles that already have powersave=1 saved).
      environment.etc."NetworkManager/dispatcher.d/20-wifi-powersave-off.sh" = {
        mode = "0755";
        text = ''
          #!/bin/sh
          # Disable WiFi power saving on every connection-up event.
          # $1 = interface, $2 = action
          [ "$2" = "up" ] || exit 0
          # Only act on WiFi interfaces
          iw dev "$1" set power_save off 2>/dev/null || true
        '';
      };

      # --- LLDP neighbor discovery (802.1AB) -----------------------------------
      # lldpd listens for LLDP (Link Layer Discovery Protocol) frames from
      # adjacent switches/routers, letting you see which switch port you're
      # plugged into, the switch's hostname/management IP, VLAN IDs, port
      # descriptions, and the full topology chain (if upstream switches also
      # run LLDP). The -c flag also enables CDP (Cisco Discovery Protocol)
      # reception for mixed-vendor environments.
      #
      # Query neighbors with:  lldpctl
      #  JSON output:          lldpctl -f json
      #  Specific interface:   lldpctl -p <iface>
      #
      # --- LLDP privacy: randomized identity ---------------------------------
      # By default lldpd advertises the real hostname (SysName=TSBW-W01800),
      # the real hardware MAC (ChassisID=mac d6:08:93:...), and the full OS
      # version (SysDescr=NixOS 26.11 ... Linux 7.1.5 ...).  The switch and
      # firewall see all of this the moment lldpd starts — before DHCP even
      # completes — defeating the DHCP hostname + MAC randomization above.
      #
      # We override all three with a random identity generated at boot:
      #   - SysName:     a random realistic device name (same generator as
      #                  the DHCP hostname, but a separate draw so the LLDP
      #                  name and DHCP name don't match)
      #   - ChassisID:   the same random name (as a string, not a MAC — so
      #                  no hardware MAC is ever leaked via LLDP)
      #   - SysDescr:    a generic description that reveals no OS/kernel info
      #
      # The boot service writes /run/lldpd-identity.conf before lldpd starts,
      # and -O makes lldpd process it at startup.  The file uses lldpcli
      # syntax (see `man lldpcli`, "CONFIGURATION FILE" section).

      # Boot service: generate a random LLDP identity before lldpd starts.
      systemd.services.lldpd-identity = {
        description = "Generate random LLDP identity for lldpd";
        before = [ "lldpd.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          RAND=$(/etc/NetworkManager/generate-random-hostname.sh)
          mkdir -p /run/lldpd
          cat > /run/lldpd/identity.conf << EOF
          configure system hostname "$RAND"
          configure system chassisid "$RAND"
          configure system description "Linux network device"
          EOF
          chmod 644 /run/lldpd/identity.conf
        '';
      };

      services.lldpd = {
        enable = true;
        # -c: also receive CDP frames (Cisco Discovery Protocol)
        # -O: process our random identity config at startup (overrides
        #     SysName, ChassisID, and SysDescr so lldpd doesn't leak the
        #     real hostname, hardware MAC, or OS version to the switch)
        # -k: don't advertise kernel release/version/machine (belt-and-
        #     suspenders for the SysDescr override above)
        extraArgs = [ "-c" "-k" "-O" "/run/lldpd/identity.conf" ];
      };

      # --- Bluetooth MAC randomization -----------------------------------------
      # NOTE: This was attempted but the Qualcomm BT controller in UwU does
      # not support BD_ADDR spoofing. btmgmt static-addr returns "Invalid
      # Parameters" and macchanger doesn't work on BT adapters at all.
      # Most consumer USB/internal BT chips hardcode the BD_ADDR in firmware.
      # If you get a BT adapter that supports it (some Intel chips do),
      # re-enable this service with btmgmt.
      #
      # systemd.services.random-bt-mac = { ... };
    }
  ;
}
