# UwU-Server host-specific user overrides.
{ inputs, ... }:
{
  nixos.hosts."UwU-Server" =
    { config, pkgs, ... }:

    {
      users.users."jaide" = {
        extraGroups = [
          "networkmanager"
          "wheel"
        ];
        # The authorized SSH key is the only bootstrap credential. Set a login
        # password with `passwd` over that authenticated session if remote sudo is
        # needed; never put a plaintext bootstrap password in the Nix store.
      };

      # Distinct central-agent fleet identity. The encrypted private key is
      # readable only by this host's SOPS identity; targets receive only the
      # public half through automationAccounts.
      sops.secrets.luna_server_ssh_private_key = {
        sopsFile = "${inputs.nixos-secrets}/secrets/UwU-Server/luna-agent.yaml";
        key = "luna_ssh_private_key";
      };
      sops.templates.luna_server_ssh_identity = {
        content = "${config.sops.placeholder.luna_server_ssh_private_key}\n";
        owner = "luna";
        group = "luna";
        mode = "0600";
      };

      # Declarative SSH config for Luna's GitHub access. Route through
      # ssh.github.com:443 since port 22 is often blocked.
      environment.etc."luna/ssh_config".text = ''
        # GitHub — route through ssh.github.com:443 (port 22 often blocked)
        Host github.com
          HostName ssh.github.com
          Port 443
          User git
          IdentityFile ~/.ssh/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
      '';

      # Generate Luna's gitconfig as a systemd oneshot that runs after SOPS
      # has rendered the private key. The signing key (public key) is derived
      # from the SOPS-managed private key via ssh-keygen -y so it is never
      # hardcoded in the Nix store.
      systemd.services.luna-gitconfig = {
        description = "Generate Luna gitconfig from SOPS-managed SSH key";
        after = [ "sops-nix.service" ];
        wants = [ "sops-nix.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
          ExecStart = pkgs.writeShellScript "luna-gitconfig" ''
            set -e
            export PATH=${pkgs.openssh}/bin:${pkgs.coreutils}/bin:$PATH
            PRIVKEY=/home/luna/.ssh/id_ed25519
            if [ ! -f "$PRIVKEY" ]; then
              echo "luna-gitconfig: private key missing, skipping"
              exit 0
            fi
            PUBKEY=$(ssh-keygen -y -f "$PRIVKEY" 2>/dev/null)
            if [ -z "$PUBKEY" ]; then
              echo "luna-gitconfig: failed to derive public key, skipping"
              exit 0
            fi
            cat > /home/luna/.gitconfig.tmp <<GITEOF
            [user]
                name = Luna
                email = luna@jaidechan.moe
                signingkey = $PUBKEY
            [core]
                sshCommand = ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519
            [commit]
                gpgsign = true
            [gpg]
                format = ssh
            [gpg "ssh"]
                program = /run/current-system/sw/bin/ssh-keygen
            GITEOF
            chown luna:luna /home/luna/.gitconfig.tmp
            chmod 644 /home/luna/.gitconfig.tmp
            mv /home/luna/.gitconfig.tmp /home/luna/.gitconfig
            echo "luna-gitconfig: generated with signing key from SOPS private key"
          '';
        };
      };

      systemd.tmpfiles.rules = [
        "d /home/luna/.ssh 0700 luna luna -"
        "L+ /home/luna/.ssh/id_ed25519 - - - - ${config.sops.templates.luna_server_ssh_identity.path}"
        "L+ /home/luna/.ssh/config - - - - /etc/luna/ssh_config"
      ];
    };
}
