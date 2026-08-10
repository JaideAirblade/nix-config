# UwU host-specific user overrides.
#
# Adds UwU-only groups (wireshark for packet capture without sudo, plus
# the shared module's defaults: networkmanager, wheel). The macrotool
# and devices modules append input/uinput/plugdev via their own
# users.users."jaide".extraGroups entries, which merge with this list.
#
# NOTE: Do NOT use lib.mkForce on extraGroups — it would override the
# merge and drop the input/uinput groups added by macrotool.nix, breaking
# evdev input capture and uinput injection.
{ inputs, ... }:
{
  nixos.hosts."UwU" =
    { config, lib, pkgs, ... }:

    {
      users.users."jaide" = {
        description = lib.mkForce "Jaide";
        # Dedicated primary group for jaide's home so luna (a member of the
        # `jaide` group) can read wallpapers and .config for the sister-sync
        # use case. Mirrors the same change in hosts/UwU-Server/users/users.nix.
        group = "jaide";
        extraGroups = [ "networkmanager" "wheel" "wireshark" "_lldpd" ];
        # Group-readable so luna can read /home/jaide.
        homeMode = "0750";
      };

      # luna is a member of the `jaide` group so group-read on /home/jaide
      # (mode 0750, primary group `jaide`) actually admits her.
      users.groups.jaide.members = [ "luna" ];

      # One-shot activation: migrate existing files in /home/jaide from the
      # old primary group (the system `users` group, gid 100, on NixOS
      # defaults) to the new `jaide` group so group-read mode 0750 actually
      # admits luna on existing files too. Idempotent — `-group 100` matches
      # nothing once everything is migrated, so re-runs are no-ops.
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

      # The Luna controller key exists only on UwU. Target devices receive
      # only its public key through the privateAccounts role.
      sops.secrets.luna_ssh_private_key.sopsFile =
        "${inputs.nixos-secrets}/secrets/UwU/luna-agent.yaml";
      sops.templates.luna_ssh_identity = {
        content = "${config.sops.placeholder.luna_ssh_private_key}\n";
        owner = "jaide";
        group = "users";
        mode = "0600";
      };
      environment.sessionVariables.LUNA_SSH_IDENTITY =
        config.sops.templates.luna_ssh_identity.path;
      # Luna's home is provisioned by the privateAccounts module
      # (nixos.modules.privateAccounts in flake.nix). Make her SSH
      # config the one rendered by nixos.modules.automationAccounts at
      # /etc/luna/ssh_config. Without this symlink, ~/.ssh/config does
      # not exist and the per-host fleet aliases (ssh uwu, ssh
      # uwu-server, ssh tsbw) defined in the automationAccounts module
      # are unreachable from interactive shells.
      #
      # The same pattern wires /home/luna/.ssh/id_ed25519 to the
      # SOPS-rendered luna identity so `ssh uwu-server` from this host
      # can actually authenticate. UwU-Server has the equivalent
      # symlink in hosts/UwU-Server/users/users.nix; UwU was missing
      # it before 2026-08-11, so SSH aliases from UwU were silently
      # broken with "no such identity" until the key was exposed.
      systemd.tmpfiles.rules = [
        "d /home/luna/.ssh 0700 luna luna -"
        "L+ /home/luna/.ssh/config - - - - /etc/luna/ssh_config"
        "L+ /home/luna/.ssh/id_ed25519 - - - - ${config.sops.templates.luna_ssh_identity.path}"
      ];
    }
  ;
}