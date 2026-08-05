# Account and authentication policy shared only by Jaide's private devices.
{ inputs, ... }:
let
  # Fleet automation is separate from Jaide's private password policy so a
  # managed work host can authorize Luna without receiving private login
  # secrets intended only for Jaide's own machines.
  automationAccounts =
    { pkgs, ... }:
    let
      migrateLunaHome = pkgs.writeShellApplication {
        name = "migrate-luna-home";
        runtimeInputs = [ pkgs.coreutils pkgs.gnutar pkgs.rsync ];
        text = ''
          set -euo pipefail
          legacy=/var/lib/luna
          target=/home/luna
          backup=/var/backups/luna-home-before-standard-home.tar

          if [[ ! -d "$legacy" ]]; then
            printf 'no legacy Luna home to migrate\n'
            exit 0
          fi
          [[ ! -L "$legacy" && -d "$target" && ! -L "$target" ]] || {
            printf 'refusing unsafe Luna home migration: source or target is invalid\n' >&2
            exit 1
          }

          install -d -m 0700 /var/backups
          if [[ ! -e "$backup" ]]; then
            tar --acls --xattrs -cpf "$backup.tmp" -C /var/lib luna
            test -s "$backup.tmp"
            mv -- "$backup.tmp" "$backup"
          fi
          test -s "$backup"
          chmod 0600 "$backup"

          rsync -aHAX --numeric-ids "$legacy/" "$target/"
          chown -R luna:luna "$target"
          chmod 0700 "$target"
          pending=$(rsync -aHAXnc --numeric-ids --itemize-changes "$legacy/" "$target/")
          [[ -z "$pending" ]] || {
            printf 'Luna home verification failed:\n%s\n' "$pending" >&2
            exit 1
          }
          printf 'Luna home copied and verified; legacy Luna home retained for rollback: %s\n' "$legacy"
        '';
      };
    in
    {
      # Root stays unavailable for direct login. Luna elevates through the
      # account-scoped sudo rule so every remote action remains attributable.
      users.users.root.hashedPassword = "!";

      # Locked SSH-only automation identity. `restrict` blocks forwarding and
      # PTY allocation, but intentionally does not force a command: together
      # with Luna's account-scoped NOPASSWD ALL rule, this key is a deliberate
      # root-equivalent fleet credential for general automation.
      users.groups.luna = { };
      users.users."luna" = {
        isNormalUser = true;
        home = "/home/luna";
        createHome = true;
        homeMode = "0700";
        autoSubUidGidRange = false;
        description = "Luna automation agent";
        group = "luna";
        extraGroups = [ "wheel" "networkmanager" ];
        shell = pkgs.bashInteractive;
        hashedPassword = "!";
        openssh.authorizedKeys.keys = [
          "restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGumwUfMQeD3XItqgrKe9RBzj6w6FqtjnD8QKImskVoQ luna-agent@UwU"
          "restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINU3saHF0DsvE0PkmQgU7sBlrfjol4R0BxaLRjZSPuRv luna-agent@UwU-Server"
        ];
      };

      security.sudo = {
        wheelNeedsPassword = true;
        extraRules = [
          {
            users = [ "luna" ];
            commands = [
              {
                command = "ALL";
                options = [ "NOPASSWD" ];
              }
            ];
          }
        ];
      };

      environment.systemPackages = [ migrateLunaHome ];
    };
in
{
  nixos.modules.automationAccounts = automationAccounts;

  nixos.modules.privateAccounts =
    { config, pkgs, ... }:
    {
      imports = [ automationAccounts ];

      # Decrypt before the users activation stage. This keeps the password hash
      # out of both Git and the world-readable Nix store.
      sops.secrets.jaide_password_hash = {
        sopsFile = "${inputs.nixos-secrets}/secrets/private/accounts.yaml";
        neededForUsers = true;
      };

      # Enforce the SOPS hash on existing accounts as well as new installs.
      # Password rotation is declarative through set-private-password-hash.sh.
      users.mutableUsers = false;
      users.users.jaide.hashedPasswordFile =
        config.sops.secrets.jaide_password_hash.path;

      # A hardware key is an alternative for graphical/TTY login, not a second
      # factor and not a way to bypass Jaide's sudo password.
      security.pam.u2f = {
        enable = false;
        control = "sufficient";
        settings = {
          cue = true;
          origin = "pam://${config.networking.hostName}";
          appid = "pam://${config.networking.hostName}";
        };
      };
      security.pam.services = {
        greetd.u2f.enable = true;
        login.u2f.enable = true;
        sudo.u2f.enable = false;
      };

      environment.systemPackages = [ pkgs.pam_u2f ];
    }
  ;
}
