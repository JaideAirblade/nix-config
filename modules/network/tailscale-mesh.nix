# Private management mesh: Tailscale supplies the encrypted network plane,
# while ordinary OpenSSH retains the existing pinned host/user key trust path.
_:
{
  nixos.modules.remoteMesh =
    { config, lib, ... }:
    let
      cfg = config.services.privateMesh;
    in
    {
      options.services.privateMesh = {
        nodeRole = lib.mkOption {
          type = lib.types.enum [ "private" "work" "printserver" ];
          description = "Access-control role assigned to this tailnet node.";
        };

        exposeSshOnLan = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Also expose OpenSSH through the host's ordinary firewall.";
        };
      };

      config = {
        services.tailscale = {
          enable = true;
          # Open the WireGuard UDP listener for direct peer-to-peer paths. The
          # tailnet policy remains deny-by-default for management traffic.
          openFirewall = true;
          useRoutingFeatures = "client";
        };

        # Do not enable Tailscale SSH: ordinary OpenSSH preserves the existing
        # authorized_keys restrictions and per-account sudo audit trail.
        services.openssh = {
          enable = true;
          openFirewall = cfg.exposeSshOnLan;
          settings = {
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
            PermitRootLogin = lib.mkDefault "no";
          };
        };

        # UwU and TSBW keep port 22 closed on LAN/public interfaces; all mesh
        # nodes accept it only on tailscale0. Hosts that deliberately retain a
        # LAN SSH path opt in with exposeSshOnLan.
        # Port 8080 is the Hermes WebUI, only exposed over the Tailscale mesh
        # (not LAN, not public internet). See tests/tailscale-mesh-regressions.py
        # for the allow-list invariant guard.
        networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 8080 ];

        # Jaide's established fleet key remains the human recovery/admin path
        # on every mesh destination. The private half never enters this repo.
        users.users.jaide.openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKozofCo3TsmA85edEMGsysfAkLf1/wWL3cv+DR0Ck04 jaide_nixos"
        ];

        # This is public role metadata, not an authentication secret. It makes
        # the required tag visible before one-time tailnet enrollment.
        environment.etc."tailscale/required-tag".text = "tag:${cfg.nodeRole}\n";
      };
    }
  ;
}
