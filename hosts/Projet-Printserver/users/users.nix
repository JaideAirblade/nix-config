# User accounts for the Projet-Printserver VM.
#
# The print server is managed via Jaide's SSH key. AD users don't need local
# accounts — SSSD resolves them from the domain after the join. The only local
# user is root for initial setup and emergency access inside the isolated lab.
#
# After the domain join, AD users can SSH in with their AD credentials
# (SSSD provides PAM authentication). To grant an AD user print admin
# rights, add them to the local lpadmin group:
#   usermod -aG lpadmin <ad-user>
_:
{
  nixos.hosts."Projet-Printserver" =
    _:

    {
      users.mutableUsers = false;
      users.users.root = {
        hashedPassword = "!";
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKozofCo3TsmA85edEMGsysfAkLf1/wWL3cv+DR0Ck04 jaide_nixos"
        ];
      };

      # Root remains available for isolated-lab bootstrap through Jaide's key.
      # PAM password auth remains enabled for non-root SSSD/AD identities;
      # PermitRootLogin keeps those methods unavailable to root.
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "prohibit-password";
          PasswordAuthentication = true;
          KbdInteractiveAuthentication = true;
          PermitEmptyPasswords = false;
        };
      };

      # Open SSH port in the firewall.
      networking.firewall.allowedTCPPorts = [ 22 ];
    }
  ;
}
