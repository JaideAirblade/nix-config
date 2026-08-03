# Account and authentication policy shared only by Jaide's private devices.
{ inputs, ... }:
{
  nixos.modules.privateAccounts =
    { config, pkgs, ... }:

    {
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

      # Root is deliberately unavailable for direct password or SSH login.
      users.users.root.hashedPassword = "!";

      # Hidden SSH-only automation identity. `restrict` blocks forwarding and
      # PTY allocation, but intentionally does not force a command: together
      # with Luna's account-scoped NOPASSWD ALL rule, this key is a deliberate
      # root-equivalent fleet credential for general automation. Its private
      # half is deployed only to the controller host UwU.
      users.groups.luna = { };
      users.users."luna" = {
        isSystemUser = true;
        description = "Luna automation agent";
        group = "luna";
        extraGroups = [ "wheel" ];
        home = "/var/lib/luna";
        createHome = true;
        shell = pkgs.bashInteractive;
        hashedPassword = "!";
        openssh.authorizedKeys.keys = [
          "restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGumwUfMQeD3XItqgrKe9RBzj6w6FqtjnD8QKImskVoQ luna-agent@UwU"
        ];
      };

      # Wheel users such as Jaide still authenticate. Only the dedicated Luna
      # account receives an account-scoped passwordless rule.
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
