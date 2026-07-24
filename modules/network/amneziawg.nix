# AmneziaWG VPN — obfuscated WireGuard for stealth remote access.
#
# AmneziaWG is a WireGuard fork with built-in protocol obfuscation:
#   - Junk packets before handshake (Jc/Jmin/Jmax)
#   - Random prefixes in handshake/data packets (S1-S4)
#   - Custom message type headers (H1-H4)
#
# This makes the traffic unrecognizable to DPI (Sophos, etc.) — it
# doesn't look like WireGuard at all.
#
# ## Architecture
#
# UwU runs the AmneziaWG SERVER. It listens on a configurable UDP port
# (default 443 for maximum stealth — looks like HTTPS-over-UDP to
# casual inspection). The VPN interface gets a 10.100.0.1/24 address.
#
# SSH listens ONLY on the VPN interface (10.100.0.1), never on LAN
# or public interfaces. Outsiders see nothing — your nftables firewall
# stays default-deny. Only the AWG UDP port is opened.
#
# ## Secrets (sops)
#
# All keys live in sops (nixos-secrets repo):
#   secrets/shared/amneziawg.yaml:
#     awg_private_key   — server private key (base64)
#     awg_preshared_key — PSK for all peers (base64)
#
# Obfuscation parameters (Jc, Jmin, Jmax, S1-S4, H1-H4) are NOT secret
# — they're in the config directly. Only the keys need protection.
#
# ## Client setup
#
# On any client device, install amneziawg-tools (or the AmneziaWG app),
# create a .conf with:
#   - The server's public key
#   - The same obfuscation parameters
#   - The PSK (from sops)
#   - Server endpoint: your-public-ip:443 (or DDNS hostname)
#
# ## Enabling per host
#
# Add to hosts/<name>/default.nix:
#   config.nixosModules.amneziawg
#   (import ./awg-client.nix)  # or use the shared server config
#
# The module is self-contained — it reads its config from sops secrets
# and sets up the interface. No key material in the Nix store.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.amneziawg-server;

  # Obfuscation parameters — NOT secret, but must match on client + server.
  # These values are chosen to effectively defeat DPI without degrading
  # performance. They're in the Nix config (not sops) so clients can
  # reference them too.
  obfuscation = {
    # Junk packets: 3-7 random packets before handshake init
    Jc = 5;
    Jmin = 50;
    Jmax = 120;
    # Random prefixes (bytes) added to each packet type
    S1 = 24;   # Init packet prefix
    S2 = 24;   # Response packet prefix
    S3 = 24;   # Cookie packet prefix
    S4 = 0;    # Data packet prefix (0 = no overhead on data)
    # Custom message type headers (must be unique, > 4)
    # These replace WireGuard's fixed type bytes (1,2,3,4)
    H1 = 928371;
    H2 = 471628;
    H3 = 192847;
    H4 = 582937;
  };
in
{
  options.services.amneziawg-server = {
    enable = lib.mkEnableOption "AmneziaWG VPN server";

    address = lib.mkOption {
      type = lib.types.str;
      default = "10.100.0.1/24";
      description = "VPN interface address (CIDR).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "UDP port to listen on. 443 for maximum stealth.";
    };

    # Peer public keys are public info — no need for sops.
    # Add more peers by extending this list.
    peers = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          publicKey = lib.mkOption {
            type = lib.types.str;
            description = "Peer's AmneziaWG public key (base64).";
          };
          allowedIPs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "10.100.0.2/32" ];
            description = "IPs this peer is allowed to use.";
          };
        };
      });
      default = [ ];
      description = "Client peers allowed to connect.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Kernel module for AmneziaWG — patched for Linux 7.x
    # (ipv6_stub removed in 7.x, replaced with ip6_dst_lookup_flow)
    # We override boot.kernelPackages to include the patched module so
    # the wg-quick NixOS module picks it up automatically.
    boot.kernelPackages = pkgs.linuxPackages.extend (kpFinal: kpPrev: {
      amneziawg = kpPrev.amneziawg.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          (pkgs.fetchpatch {
            url = "https://github.com/amnezia-vpn/amneziawg-linux-kernel-module/commit/60c1bd0105246bbd309e5148f1399ac41c8ffd9f.patch";
            hash = "sha256-foDqFTt2jy8V8SF3674iBniodzMrWTiMEtH/rdjzFj0=";
          })
          (pkgs.fetchpatch {
            url = "https://github.com/amnezia-vpn/amneziawg-linux-kernel-module/commit/40b04a8d43f1e24ed6e495a5a97c05883ab1d122.patch";
            hash = "sha256-gP20swVf5vddqEbkwmx0jsaPJsrQud8NvK6x+4jHtF8=";
          })
        ];
      });
    });
    environment.systemPackages = [ pkgs.amneziawg-tools ];

    # AmneziaWG interface via wg-quick with type = "amneziawg"
    networking.wg-quick.interfaces.awg0 = {
      type = "amneziawg";
      address = [ cfg.address ];
      listenPort = cfg.port;
      privateKeyFile = "/run/secrets/awg_private_key";

      # Open the UDP port in nftables (insert before the default drop)
      postUp = ''
        # Allow incoming AmneziaWG traffic on the configured port
        nft insert rule inet filter input udp dport ${toString cfg.port} accept
      '';
      preDown = ''
        nft delete rule inet filter input udp dport ${toString cfg.port} accept 2>/dev/null || true
      '';

      # Obfuscation parameters — applied via awg setconf after interface is up
      # wg-quick doesn't natively understand AWG params, so we set them post-up.
      # We write a temp config snippet and apply it with awg setconf.
      peers = map (peer: {
        inherit (peer) publicKey allowedIPs;
        presharedKeyFile = "/run/secrets/awg_preshared_key";
        persistentKeepalive = 25;
      }) cfg.peers;
    };

    # Apply AmneziaWG obfuscation parameters after interface is up.
    # wg-quick handles the basic interface + peers, but the AWG-specific
    # obfuscation params need to be set via awg setconf.
    systemd.services.awg-obfuscation = {
      description = "Apply AmneziaWG obfuscation parameters";
      after = [ "wg-quick-awg0.service" ];
      bindsTo = [ "wg-quick-awg0.service" ];
      wantedBy = [ "multi-user.target" ];
      script = ''
        # Wait for interface to exist
        for i in $(seq 1 10); do
          if ip link show awg0 >/dev/null 2>&1; then break; fi
          sleep 0.5
        done

        # Apply obfuscation parameters
        ${pkgs.amneziawg-tools}/bin/awg set awg0 \
          Jc ${toString obfuscation.Jc} \
          Jmin ${toString obfuscation.Jmin} \
          Jmax ${toString obfuscation.Jmax} \
          S1 ${toString obfuscation.S1} \
          S2 ${toString obfuscation.S2} \
          S3 ${toString obfuscation.S3} \
          S4 ${toString obfuscation.S4} \
          H1 ${toString obfuscation.H1} \
          H2 ${toString obfuscation.H2} \
          H3 ${toString obfuscation.H3} \
          H4 ${toString obfuscation.H4}
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # Export obfuscation params as a system file so client config generation
    # can reference them without duplicating values.
    environment.etc."amneziawg/obfuscation.conf".text = lib.concatStringsSep "\n" [
      "Jc = ${toString obfuscation.Jc}"
      "Jmin = ${toString obfuscation.Jmin}"
      "Jmax = ${toString obfuscation.Jmax}"
      "S1 = ${toString obfuscation.S1}"
      "S2 = ${toString obfuscation.S2}"
      "S3 = ${toString obfuscation.S3}"
      "S4 = ${toString obfuscation.S4}"
      "H1 = ${toString obfuscation.H1}"
      "H2 = ${toString obfuscation.H2}"
      "H3 = ${toString obfuscation.H3}"
      "H4 = ${toString obfuscation.H4}"
    ];
  };
}