# AmneziaWG full mesh VPN — every host is both server and client.
#
# ## Architecture
#
# TRUE FULL MESH: every host runs an AWG server (listens on UDP 443)
# and has peer entries for every other host. Each host can reach every
# other host directly — no hub, no relay, no single point of failure.
#
# Each host gets:
#   - Its own keypair (private key in sops, public key in config)
#   - Its own VPN IP (10.100.0.N)
#   - ONE awg0 interface that both listens (server) AND dials (client)
#   - Peer entries for ALL other hosts in the mesh
#
# WireGuard/AWG is bi-directional — the "server" (listenPort) and
# "client" (endpoint) roles are just for the initial handshake. After
# that, both sides can send/receive freely. So one interface with N-1
# peers gives full mesh connectivity.
#
# ## Reachability
#
# In a perfect world, every host has a stable public endpoint (port
# forwarded or UPnP). In practice:
#   - Hosts with UPnP auto-forward 443 → reachable from anywhere
#   - Hosts behind NAT without UPnP → NOT reachable for incoming
#     connections, but CAN dial out to reachable hosts
#   - WireGuard learns roaming endpoints from source packets
#
# So: if UwU and OwO are reachable (UPnP), TSBW (behind corp NAT)
# can dial both. UwU and OwO can dial each other. TSBW can't be
# dialed directly, but once it dials out, its endpoint is learned
# and return traffic works.
#
# ## VPN IP allocation
#
#   UwU          → 10.100.0.1
#   TSBW-W01800  → 10.100.0.2
#   OwO-Family   → 10.100.0.3
#   phone        → 10.100.0.10 (manual .conf import)
#   laptop       → 10.100.0.11 (manual .conf import)
#
# ## Secrets (sops)
#
# File: secrets/shared/amneziawg.yaml in nixos-secrets repo.
#   awg_private_key_<hostname> — per-host private key (base64)
#   awg_preshared_key          — shared PSK for all peers (base64)
#
# Public keys are NOT secret — in config. Obfuscation params NOT secret.
#
# ## Enabling
#
# Add to hosts/<name>/default.nix:
#   config.nixosModules.amneziawg-mesh
#   {
#     services.amneziawg-mesh = {
#       enable = true;
#       thisHost = "UwU";
#       endpoint = "your.public.ip:443";  # or DDNS hostname
#       hosts = {
#         UwU         = { vpnIP = "10.100.0.1"; publicKey = "..."; endpoint = "uwu.example.com"; };
#         TSBW-W01800 = { vpnIP = "10.100.0.2"; publicKey = "..."; endpoint = ""; };  # roaming
#         OwO-Family  = { vpnIP = "10.100.0.3"; publicKey = "..."; endpoint = "owo.example.com"; };
#       };
#     };
#   }
{ config, lib, pkgs, ... }:

let
  cfg = config.services.amneziawg-mesh;

  # Obfuscation parameters — NOT secret, must match on all peers.
  obfuscation = {
    Jc = 5; Jmin = 50; Jmax = 120;
    S1 = 24; S2 = 24; S3 = 24; S4 = 0;
    H1 = 928371; H2 = 471628; H3 = 192847; H4 = 582937;
  };

  thisHostCfg = cfg.hosts.${cfg.thisHost} or (throw "amneziawg-mesh: thisHost '${cfg.thisHost}' not in hosts");
  otherHosts = lib.filterAttrs (name: _: name != cfg.thisHost) cfg.hosts;

  # Sops secret name for this host's private key (sops keys can't have hyphens)
  sopsKey = if cfg.privateKeySecret != "" then cfg.privateKeySecret
            else "awg_private_key_${builtins.replaceStrings ["-"] ["_"] cfg.thisHost}";

  ifName = "awg0";
in
{
  options.services.amneziawg-mesh = {
    enable = lib.mkEnableOption "AmneziaWG full mesh VPN";

    thisHost = lib.mkOption {
      type = lib.types.str;
      description = "Hostname of this machine (must be a key in hosts).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "UDP port for AWG server. 443 for stealth.";
    };

    privateKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Name of the sops secret containing this host's AWG private key.
        If empty, defaults to awg_private_key_<thisHost> (hyphens → underscores).
        Override during migration if the old key name is still in use.
      '';
    };

    hosts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          vpnIP = lib.mkOption {
            type = lib.types.str;
            description = "VPN IP (no CIDR).";
          };
          publicKey = lib.mkOption {
            type = lib.types.str;
            description = "AWG public key (base64).";
          };
          endpoint = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = ''
              Public endpoint (IP or DDNS:port) for this host.
              Empty = roaming host (no stable endpoint, relies on
              WireGuard endpoint learning from outgoing packets).
            '';
          };
        };
      });
      default = { };
      description = "All hosts in the mesh.";
    };

    enableUPnP = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Auto-forward UDP port via UPnP (if router supports it).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.amneziawg-tools ]
      ++ lib.optional cfg.enableUPnP pkgs.miniupnpc;

    # ── Full mesh interface ────────────────────────────────────────
    # ONE interface: listens on 443 (server) AND has peers for all
    # other hosts (client). WireGuard is bi-directional, so this gives
    # full mesh connectivity with a single interface per host.
    networking.wg-quick.interfaces.${ifName} = {
      type = "amneziawg";
      address = [ "${thisHostCfg.vpnIP}/24" ];
      listenPort = cfg.port;
      privateKeyFile = "/run/secrets/${sopsKey}";

      postUp = ''
        # Open AWG port in nftables
        nft insert rule inet filter input udp dport ${toString cfg.port} accept 2>/dev/null || true
      '' + lib.optionalString cfg.enableUPnP ''
        # Auto-forward via UPnP
        ${pkgs.miniupnpc}/bin/upnpc -a 0.0.0.0 ${toString cfg.port} ${toString cfg.port} UDP 3600 2>/dev/null || true
      '';

      preDown = ''
        nft delete rule inet filter input udp dport ${toString cfg.port} accept 2>/dev/null || true
      '' + lib.optionalString cfg.enableUPnP ''
        ${pkgs.miniupnpc}/bin/upnpc -d ${toString cfg.port} UDP 2>/dev/null || true
      '';

      # Peer entry for every other host in the mesh.
      # Use lib.optional to OMIT the endpoint key entirely when empty —
      # writing Endpoint= (empty value) causes AWG to reject the config.
      peers = lib.mapAttrsToList (name: hostCfg: ({
        publicKey = hostCfg.publicKey;
        allowedIPs = [ "${hostCfg.vpnIP}/32" ];
        presharedKeyFile = "/run/secrets/awg_preshared_key";
        persistentKeepalive = 25;
      } // lib.optionalAttrs (hostCfg.endpoint != "") {
        endpoint = hostCfg.endpoint;
      })) otherHosts;
    };

    # ── Apply obfuscation params after interface is up ──────────────
    systemd.services.awg-obfuscation = {
      description = "Apply AmneziaWG obfuscation parameters";
      after = [ "wg-quick-${ifName}.service" ];
      bindsTo = [ "wg-quick-${ifName}.service" ];
      wantedBy = [ "multi-user.target" ];
      script = ''
        for i in $(seq 1 10); do
          if ip link show ${ifName} >/dev/null 2>&1; then break; fi
          sleep 0.5
        done
        ${pkgs.amneziawg-tools}/bin/awg set ${ifName} \
          jc ${toString obfuscation.Jc} \
          jmin ${toString obfuscation.Jmin} \
          jmax ${toString obfuscation.Jmax} \
          s1 ${toString obfuscation.S1} \
          s2 ${toString obfuscation.S2} \
          s3 ${toString obfuscation.S3} \
          s4 ${toString obfuscation.S4} \
          h1 ${toString obfuscation.H1} \
          h2 ${toString obfuscation.H2} \
          h3 ${toString obfuscation.H3} \
          h4 ${toString obfuscation.H4}
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # ── UPnP lease renewal timer ────────────────────────────────────
    systemd.services.awg-upnp-renew = lib.mkIf cfg.enableUPnP {
      description = "Renew UPnP port forwarding for AWG";
      after = [ "wg-quick-${ifName}.service" ];
      bindsTo = [ "wg-quick-${ifName}.service" ];
      script = ''
        ${pkgs.miniupnpc}/bin/upnpc -a 0.0.0.0 ${toString cfg.port} ${toString cfg.port} UDP 3600 2>/dev/null || true
      '';
      serviceConfig.Type = "oneshot";
    };

    systemd.timers.awg-upnp-renew = lib.mkIf cfg.enableUPnP {
      description = "Renew UPnP lease every 5 minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "5min";
        Unit = "awg-upnp-renew.service";
      };
    };

    # ── Enable IP forwarding (so this host can be an exit point) ────
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
    };

    # ── SOPS secrets ────────────────────────────────────────────────
    # The per-host private key — secrets.nix handles the sopsFile path
    # and the shared PSK. We only set the restartUnits here to avoid
    # conflicting sopsFile definitions.
    sops.secrets.${sopsKey}.restartUnits = [ "wg-quick-${ifName}.service" ];
    sops.secrets.awg_preshared_key.restartUnits = [ "wg-quick-${ifName}.service" ];

    # ── Export obfuscation params for reference ─────────────────────
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

    # ── Client .conf generator script ───────────────────────────────
    # Generates .conf files for phone/laptop import. One per target host.
    environment.etc."amneziawg/generate-client-conf.sh".text = ''
      #!/usr/bin/env bash
      # Generate an AWG client .conf for connecting to a specific mesh host.
      # Usage: sudo /etc/amneziawg/generate-client-conf.sh <hostname> <client-ip>
      # Example: sudo /etc/amneziawg/generate-client-conf.sh UwU 10.100.0.10
      set -euo pipefail

      TARGET="''${1:-}"
      CLIENT_IP="''${2:-}"

      if [ -z "$TARGET" ] || [ -z "$CLIENT_IP" ]; then
        echo "Usage: $0 <hostname> <client-ip>"
        echo ""
        echo "Available target hosts:"
      '' + lib.concatStringsSep "\n" (lib.mapAttrsToList (name: hcfg: ''
        echo "  ${name}  →  ${hcfg.vpnIP}  endpoint: ${if hcfg.endpoint != "" then hcfg.endpoint else "(roaming — no stable endpoint)"}"
      '') cfg.hosts) + ''
        echo ""
        echo "Suggested client IPs: 10.100.0.10 (phone), 10.100.0.11 (laptop), etc."
        exit 1
      fi

      PSK=$(cat /run/secrets/awg_preshared_key 2>/dev/null || echo "<NOT_FOUND>")
      TARGET_KEY="$(grep '^${"\${TARGET}"},' /etc/amneziawg/hosts.csv 2>/dev/null | cut -d, -f3 || echo "")"
      TARGET_ENDPOINT="$(grep '^${"\${TARGET}"},' /etc/amneziawg/hosts.csv 2>/dev/null | cut -d, -f4 || echo "")"

      if [ -z "$TARGET_KEY" ]; then
        echo "ERROR: Target host '$TARGET' not found in /etc/amneziawg/hosts.csv"
        exit 1
      fi

      echo "# AmneziaWG client config → $TARGET"
      echo "# Generated $(date)"
      echo "# Import into AmneziaWG app or: wg-quick up /path/to/this.conf"
      echo ""
      echo "[Interface]"
      echo "PrivateKey = <INSERT_YOUR_PRIVATE_KEY>"
      echo "Address = $CLIENT_IP/24"
      echo "MTU = 1420"
      echo ""
      echo "[Peer]"
      echo "# Target: $TARGET"
      echo "PublicKey = $TARGET_KEY"
      echo "PresharedKey = $PSK"
      if [ -n "$TARGET_ENDPOINT" ]; then
        echo "Endpoint = $TARGET_ENDPOINT"
      else
        echo "# Endpoint = (roaming host — no stable endpoint, connect when on same network)"
      fi
      echo "AllowedIPs = 10.100.0.0/24"
      echo "PersistentKeepalive = 25"
      echo ""
      echo "# Obfuscation parameters"
      echo "Jc = ${toString obfuscation.Jc}"
      echo "Jmin = ${toString obfuscation.Jmin}"
      echo "Jmax = ${toString obfuscation.Jmax}"
      echo "S1 = ${toString obfuscation.S1}"
      echo "S2 = ${toString obfuscation.S2}"
      echo "S3 = ${toString obfuscation.S3}"
      echo "S4 = ${toString obfuscation.S4}"
      echo "H1 = ${toString obfuscation.H1}"
      echo "H2 = ${toString obfuscation.H2}"
      echo "H3 = ${toString obfuscation.H3}"
      echo "H4 = ${toString obfuscation.H4}"
    '';

    # ── Hosts CSV (for the .conf generator script) ──────────────────
    environment.etc."amneziawg/hosts.csv".text =
      lib.concatStringsSep "\n" (lib.mapAttrsToList (name: hcfg: ''
        ${name},${hcfg.vpnIP},${hcfg.publicKey},${hcfg.endpoint}
      '') cfg.hosts);
  };
}