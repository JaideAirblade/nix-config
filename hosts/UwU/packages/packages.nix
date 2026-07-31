# UwU host-specific packages.
#
# Imports the shared packages subfolders (file-manager, onepassword,
# network-tools, media) that UwU wants, and adds UwU-only GUI apps that
# the work host doesn't need (Legcord, Seanime, Geary, Chromium
# for WebHID, etc.).
_:
{
  nixos.hosts."UwU" =
    { pkgs, lib, ... }:

    {
      # Shared package modules (file-manager, onepassword, network-tools,
      # osint, media) are imported by the host entry point (default.nix)
      # via config.nixosModules.packages-* — not via imports here.

      # DMS searches the system Flatpak export before /run/current-system in
      # XDG_DATA_DIRS. Shadow the stock NymVPN entry in XDG_DATA_HOME so the
      # launcher resolves our no-splash entry instead of the crashing one.
      systemd.user.tmpfiles.rules = [
        "d %h/.local/share/applications 0755 - - -"
        "L+ %h/.local/share/applications/net.nymtech.NymVPN.desktop - - - - /run/current-system/sw/share/applications/net.nymtech.NymVPN.desktop"
      ];

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

        # Legcord — force XWayland via desktop entry override.
        # NIXOS_OZONE_WL=1 (set globally in theming.nix) makes Electron apps
        # try native Wayland. On NVIDIA + MangoWM, Legcord flickers badly in
        # native Wayland mode (libEGL dri2 screen failures + compositor
        # re-allocation on every frame). XWayland is stable. hiPrio shadows
        # the upstream .desktop file.
        (lib.hiPrio (makeDesktopItem {
          name = "legcord";
          desktopName = "Legcord";
          genericName = "Internet Messenger";
          comment = "Lightweight, alternative desktop client for Discord";
          icon = "legcord";
          categories = [ "Network" "InstantMessaging" ];
          exec = "legcord --ozone-platform=x11 %U";
          startupNotify = true;
          mimeTypes = [ "x-scheme-handler/discord" ];
        }))

        # Legcord 1.3.0 — packaged from the upstream AppImage until nixpkgs
        # catches up (the pinned nixpkgs package is currently 1.2.4).
        legcord

        # Orbolay — native Discord voice overlay. Keep it alongside Legcord;
        # it is a separate overlay utility, not a Discord client replacement.
        orbolay

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

        # Helium — private Chromium-based browser. Keep this declaration in
        # the flake so rebuilds cannot silently drop the browser or its profile.
        helium-bin

        # NymVPN GUI workarounds (GNOME 49 Flatpak runtime):
        # 1. --nosplash avoids the splash window, which historically
        #    triggered the glycin SVG loader crash.
        # 2. REQUIRED: ~/.var/app/net.nymtech.NymVPN/config/gtk-3.0/settings.ini
        #    pins gtk-icon-theme-name=Adwaita. With the host Papirus theme
        #    (a /nix/store symlink farm exposed via /run/host/share/icons),
        #    gdk-pixbuf 2.44's sandboxed glycin loader dies on the
        #    image-missing.svg fallback and GTK aborts the whole app before
        #    the window appears. (Verified 2026-07-31.)
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

      # Restore the Btrfs snapshot policy used by the previous UwU generation.
      # The module also installs snapper, snapperd, snbk, and mksubvolume.
      services.snapper = {
        configs = {
          home = {
            SUBVOLUME = "/home";
            FSTYPE = "btrfs";
            ALLOW_USERS = [ "jaide" ];
            TIMELINE_CLEANUP = true;
            TIMELINE_CREATE = true;
            TIMELINE_LIMIT_HOURLY = 10;
            TIMELINE_LIMIT_DAILY = 14;
            TIMELINE_LIMIT_WEEKLY = 4;
            TIMELINE_LIMIT_MONTHLY = 3;
            TIMELINE_LIMIT_YEARLY = 0;
          };
          root = {
            SUBVOLUME = "/";
            FSTYPE = "btrfs";
            ALLOW_USERS = [ "jaide" ];
            TIMELINE_CLEANUP = true;
            TIMELINE_CREATE = true;
            TIMELINE_LIMIT_HOURLY = 5;
            TIMELINE_LIMIT_DAILY = 7;
            TIMELINE_LIMIT_WEEKLY = 4;
            TIMELINE_LIMIT_MONTHLY = 0;
            TIMELINE_LIMIT_YEARLY = 0;
          };
        };
      };

      # /home is a separate Btrfs subvolume, so provision its Snapper
      # .snapshots subvolume before the timeline/cleanup services run.
      # This is idempotent and never replaces an existing snapshot tree.
      systemd.services.snapper-home-subvolume = {
        description = "Provision the /home Snapper subvolume";
        wantedBy = [ "local-fs.target" ];
        requires = [ "home.mount" ];
        after = [ "home.mount" ];
        before = [ "snapper-timeline.service" "snapper-cleanup.service" ];
        path = [ pkgs.btrfs-progs pkgs.coreutils ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          if [ ! -e /home/.snapshots ]; then
            btrfs subvolume create /home/.snapshots
          fi
          chown root:root /home/.snapshots
          chmod 755 /home/.snapshots
        '';
      };

      # Nym creates and configures its TUN interfaces itself. If NetworkManager
      # adopts them as external profiles, it rebuilds the links and removes
      # Nym's table-333 routes shortly after they are installed.
      networking.networkmanager.unmanaged = [ "interface-name:tun*" ];

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
