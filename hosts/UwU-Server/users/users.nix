# UwU-Server host-specific user overrides.
{ inputs, ... }:
{
  nixos.hosts."UwU-Server" =
    { config, pkgs, lib, ... }:

    {
      users.users."jaide" = {
        # Dedicated primary group for jaide's home so luna (a member of the
        # `jaide` group) can read wallpapers and .config for the sister-sync
        # use case. Switching from the system `users` group to a dedicated
        # `jaide` group keeps the trust boundary explicit and avoids polluting
        # the shared `users` group with personal-account membership.
        group = "jaide";
        extraGroups = [
          "networkmanager"
          "wheel"
        ];
        # Group-readable so luna can read /home/jaide. The home contains
        # sensitive material (.ssh, .local/share/keyring, browser profile,
        # .gnupg) — luna is a trusted fleet identity, not a sandboxed agent,
        # and the access is read-only in practice (luna never writes here as
        # part of normal operation).
        homeMode = "0750";
        # The authorized SSH key is the only bootstrap credential. Set a login
        # password with `passwd` over that authenticated session if remote sudo is
        # needed; never put a plaintext bootstrap password in the Nix store.
      };

      # luna is a member of the `jaide` group so group-read on /home/jaide
      # (mode 0750, primary group `jaide`) actually admits her. This is the
      # NixOS-idiomatic way to share home access between two human accounts
      # without either account touching the other's primary group.
      users.groups.jaide.members = [ "luna" ];

      # One-shot activation: migrate existing files in /home/jaide from the
      # old primary group (the system `users` group, gid 100, on NixOS
      # defaults) to the new `jaide` group so group-read mode 0750 actually
      # admits luna on existing files too. Idempotent — `--from-group users`
      # is a no-op once everything is migrated.
      systemd.services.migrate-jaide-home-group = {
        description = "Migrate /home/jaide file ownership to the jaide group";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
          ExecStart = pkgs.writeShellScript "migrate-jaide-home-group" ''
            set -euo pipefail
            target=/home/jaide
            [[ -d "$target" ]] || { echo "no $target, skipping"; exit 0; }
            # Only chown files whose group is still the old `users` group
            # (gid 100 on NixOS defaults). Leave everything else alone —
            # this is a one-shot migration, not a recurring chown.
            ${pkgs.findutils}/bin/find "$target" -xdev \
              ! -group users -prune -o \
              -group 100 -exec ${pkgs.coreutils}/bin/chown :jaide {} +
            echo "migrate-jaide-home-group: complete"
          '';
        };
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

      # graphify lives in a per-user pip venv at ~/.local/share/graphify-venv
      # (system python3, no home-manager, PEP 668 doesn't bite because the
      # venv is a clean site). The symlink at ~/.local/bin/graphify is what
      # ~/.local/bin/graphify resolves to, so ~/.local/bin needs to be on
      # PATH. The lib.mkBefore keeps user overrides ahead of the system
      # default PATH prefix order so `graphify` here always wins over any
      # future global install.
      environment.sessionVariables.PATH = lib.mkBefore [
        "/home/luna/.local/bin"
      ];

      # Declarative SSH config for Luna — provided by
      # nixos.modules.automationAccounts (modules/users/private-accounts.nix).
      # The render target is /etc/luna/ssh_config, and the symlink below
      # makes ~/.ssh/config point at it.

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

        # ── Sister-sync: jaide's Games directory lives on the dedicated games
        # volume (/media/games, btrfs subvol on /dev/nvme2n1p1) so SEBNS's 54G
        # Wine prefix and Steam library don't bloat the root pool's @/home
        # subvol. /home/jaide/Games is a managed symlink into that volume —
        # Heroic / Steam / Lutris resolve the canonical path
        # /home/jaide/Games/Heroic/Prefixes/SEBNS the same way they would on
        # UwU, where Games lives directly under /home.
        #
        # The symlink is idempotent and survives redeploys: tmpfiles.d treats
        # an already-present file/symlink as a no-op for 'L+' entries when
        # the target path resolves correctly. Initial creation requires the
        # target directory to exist; disko + a jaide-writable /media/games
        # provide that.
        "d /media/games/jaide/Games 0750 jaide jaide -"
        "d /media/games/jaide/Games/Heroic 0750 jaide jaide -"
        "d /media/games/jaide/Games/Heroic/Prefixes 0750 jaide jaide -"
        "L+ /home/jaide/Games - - - - /media/games/jaide/Games"
      ];
    };
}
