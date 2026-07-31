# UwU host-specific packages.
#
# Imports the shared packages subfolders (file-manager, onepassword,
# network-tools, media) that UwU wants, and adds UwU-only GUI apps that
# the work host doesn't need (Equibop, Seanime, Geary, Chromium
# for WebHID, etc.).
_:
{
  nixos.hosts."UwU" =
    { pkgs, lib, ... }:

    {
      # Shared package modules (file-manager, onepassword, network-tools,
      # osint, media) are imported by the host entry point (default.nix)
      # via config.nixosModules.packages-* — not via imports here.

      environment.systemPackages = with pkgs; [
        # IVPN UI desktop entry override — force X11 + --disable-gpu.
        # The stock ivpn-ui wrapper honours NIXOS_OZONE_WL=1 (set globally in
        # theming.nix) and adds --ozone-platform-hint=auto, which makes Electron
        # try native Wayland. On MangoWM that crashes with a Vulkan/Wayland
        # incompatibility, killing the UI (including the close/disconnect dialog).
        # hiPrio shadows the upstream .desktop file so app launchers pick this one.
        (lib.hiPrio (makeDesktopItem {
          name = "ivpn-ui";
          desktopName = "IVPN";
          genericName = "VPN Client";
          comment = "UI interface for IVPN";
          icon = "ivpn-ui";
          categories = [ "Network" ];
          exec = "ivpn-ui --ozone-platform=x11 --disable-gpu";
          startupNotify = true;
        }))

        # Equibop — force XWayland via desktop entry override.
        # NIXOS_OZONE_WL=1 (set globally in theming.nix) makes Electron apps
        # try native Wayland. On NVIDIA + MangoWM, Equibop flickers badly in
        # native Wayland mode (libEGL dri2 screen failures + compositor
        # re-allocation on every frame). XWayland is stable. hiPrio shadows
        # the upstream .desktop file.
        (lib.hiPrio (makeDesktopItem {
          name = "equibop";
          desktopName = "Equibop";
          genericName = "Internet Messenger";
          comment = "Discord client with Equicord preinstalled";
          icon = "equibop";
          categories = [ "Network" "InstantMessaging" ];
          exec = "equibop --ozone-platform=x11";
          startupNotify = true;
          mimeTypes = [ "x-scheme-handler/discord" ];
        }))

        # Equibop — Discord desktop client with Equicord preinstalled.
        # It is based on Vesktop and has native Linux improvements.
        equibop

        # Readest — modern ebook reader.
        readest

        # Calibre — ebook management. Used with ACSM Input + DeDRM plugins
        # to download EPUBs from Google Play Books (ACSM → DRM-free EPUB).
        calibre

        # --- Disk health monitoring (TSBW has these via disk-recovery.nix) ---
        smartmontools # smartctl — SMART health for HDD/SSD
        nvme-cli # nvme smart-log — NVMe health & controller logs

        # --- GPU monitor for NVIDIA 3080 (TSBW has nvtopPackages.amd) ---
        nvtopPackages.nvidia

        # --- System info (TSBW has this in system-packages.nix) ---
        fastfetch

        # NymVPN daemon and core networking helpers. The GUI client is managed
        # separately through Flathub in flatpak.nix.
        nym-vpnd

        # Pear Desktop — the renamed YouTube Music client. Its stock Electron
        # launcher tries native Wayland on this NVIDIA/MangoWM setup and can
        # fail during GPU-process startup, so the launcher below forces X11.
        (lib.hiPrio (makeDesktopItem {
          name = "pear-desktop";
          desktopName = "Pear Desktop";
          genericName = "YouTube Music Client";
          comment = "YouTube Music desktop client";
          icon = "pear-desktop";
          categories = [ "AudioVideo" "Audio" ];
          exec = "pear-desktop --ozone-platform=x11 --disable-gpu %U";
          startupNotify = true;
        }))
        pear-desktop

        # NymVPN's Flatpak splash window triggers the GNOME 49 Glycin SVG
        # loader crash on this host. The main window works with --nosplash.
        (lib.hiPrio (makeDesktopItem {
          name = "net.nymtech.NymVPN";
          desktopName = "NymVPN";
          genericName = "Privacy VPN";
          comment = "Decentralized, mixnet, and zero-knowledge VPN";
          icon = "net.nymtech.NymVPN";
          categories = [ "Network" ];
          exec = "flatpak run net.nymtech.NymVPN --nosplash";
          startupNotify = true;
        }))

        # Chromium — force XWayland via desktop entry overrides.
        # NIXOS_OZONE_WL=1 (set globally in theming.nix) makes Chromium try native
        # Wayland, which on NVIDIA + MangoWM flickers and produces visual artifacts
        # (MangoWM issue #1181 — same root cause as the Discord override above).
        # XWayland is stable.
        #
        # We shadow BOTH upstream .desktop files:
        #   chromium.desktop        — used by app launchers
        #   chromium-browser.desktop — used by xdg-mime as the default HTTP handler
        # Without shadowing the second one, links clicked from Discord/other apps
        # launch the unpatched entry → native Wayland → GPU segfaults in
        # libnvidia-eglcore.so → compositor flicker. hiPrio ensures both override.
        (lib.hiPrio (makeDesktopItem {
          name = "chromium";
          desktopName = "Chromium";
          genericName = "Web Browser";
          comment = "Chromium browser (XWayland)";
          icon = "chromium";
          categories = [ "Network" "WebBrowser" ];
          exec = "chromium --ozone-platform=x11";
          startupNotify = true;
          mimeTypes = [
            "x-scheme-handler/http"
            "x-scheme-handler/https"
            "x-scheme-handler/ftp"
            "text/html"
            "text/xml"
            "application/xhtml+xml"
          ];
        }))
        (lib.hiPrio (makeDesktopItem {
          name = "chromium-browser";
          desktopName = "Chromium";
          genericName = "Web Browser";
          comment = "Chromium browser (XWayland)";
          icon = "chromium";
          categories = [ "Network" "WebBrowser" ];
          exec = "chromium --ozone-platform=x11 %U";
          startupNotify = true;
          startupWMClass = "chromium-browser";
          noDisplay = true;
          mimeTypes = [
            "x-scheme-handler/http"
            "x-scheme-handler/https"
            "x-scheme-handler/ftp"
            "text/html"
            "text/xml"
            "application/xhtml+xml"
          ];
        }))

        # The actual chromium binary (the desktop entries above just shadow the
        # upstream .desktop files to add --ozone-platform=x11).
        chromium

        # Seanime — self-hosted anime/manga media server (desktop app + web UI).
        seanime

        # Octarine — private markdown note-taking app (custom package from pkgs/).
        octarine

        # Zed — GPU-accelerated collaborative code editor.
        zed-editor

        # Geary — GTK email client. Follows libadwinda/GNOME theming, fits the
        # standalone-WM + adw-gtk3-dark setup without pulling all of GNOME.
        geary

        # Hytale Launcher — official launcher for Hytale (custom package from pkgs/).
        # Wrapped in buildFHSEnv so the pre-built binary finds its libraries.
        hytale

        # Galaxy Buds Client — unofficial manager for Samsung Galaxy Buds earbuds.
        # EQ, ANC/ambient, touch actions, battery stats, diagnostics over RFCOMM/SPP.
        # Confirmed working with Buds4 Pro (PR #689, v5.2+).
        galaxy-buds-client
      ];

      # NymVPN's daemon expects these networking tools in its isolated
      # systemd PATH on NixOS.
      systemd.services.nym-vpnd = {
        description = "NymVPN daemon";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" "NetworkManager.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [
          pkgs.iproute2
          pkgs.iptables
          pkgs.nftables
          pkgs.coreutils
        ];
        serviceConfig = {
          ExecStart = "${pkgs.nym-vpnd}/bin/nym-vpnd";
          Restart = "on-failure";
          RestartSec = 5;
          AmbientCapabilities = [
            "CAP_NET_ADMIN"
            "CAP_NET_RAW"
            "CAP_NET_BIND_SERVICE"
          ];
          CapabilityBoundingSet = [
            "CAP_NET_ADMIN"
            "CAP_NET_RAW"
            "CAP_NET_BIND_SERVICE"
          ];
        };
      };

      # NymVPN creates a TUN device for the system tunnel.
      boot.kernelModules = [ "tun" ];

      # nym-vpnd creates this policy dynamically under /usr/share, but NixOS
      # polkit does not scan that mutable path. Install the action declaratively
      # in /etc so the GUI's unix-socket authentication is registered.
      environment.etc."polkit-1/actions/com.nymvpn.vpnd.unix-access.policy".text = ''
        <?xml version="1.0" encoding="UTF-8"?>
        <policyconfig>
          <action id="com.nymvpn.vpnd.unix-access">
            <description>Connect via unix socket</description>
            <message>Authentication is required to connect to the daemon</message>
            <defaults>
              <allow_any>auth_admin</allow_any>
              <allow_inactive>auth_admin</allow_inactive>
              <allow_active>auth_self</allow_active>
            </defaults>
          </action>
        </policyconfig>
      '';

      # Permit the logged-in desktop user to communicate with nym-vpnd.
      # DMS already provides the authentication agent for this host.
      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "com.nymvpn.vpnd.unix-access" &&
              subject.user == "jaide") {
            return polkit.Result.YES;
          }
        });
      '';
    }
  ;
}
