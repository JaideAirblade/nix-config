# SSH server + remote access for UwU-Server.
#
# This box is meant to be administrable headlessly over SSH (and eventually
# used remotely). Key-only auth: jaide's GitHub/SSH keypair is deployed to the
# box via sops (modules/secrets), and the matching public key is authorized
# here for login FROM her other machines.
_:
{
  nixos.hosts."UwU-Server" =
    _:

    {
      # jaide can add locally-built (unsigned) closures to the store — required
      # for `nixos-rebuild --target-host jaide@... --use-remote-sudo` deploys.
      nix.settings.trusted-users = [ "jaide" ];

      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
      };

      users.users."jaide".openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKozofCo3TsmA85edEMGsysfAkLf1/wWL3cv+DR0Ck04 jaide_nixos"
      ];
    }
  ;
}
