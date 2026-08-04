# User accounts for the Projet-Printserver VM.
#
# The print server is managed via SSH with a root password set during
# VM creation. AD users don't need local accounts — SSSD resolves them
# from the domain after the join. The only local user is root for
# initial setup and emergency access.
#
# After the domain join, AD users can SSH in with their AD credentials
# (SSSD provides PAM authentication). To grant an AD user print admin
# rights, add them to the local lpadmin group:
#   usermod -aG lpadmin <ad-user>
_:
{
  nixos.hosts."Projet-Printserver" =
    { ... }:

    {
      # Root login with empty password for lab VM testing.
      # In production, set a real password or use SSH keys.
      users.mutableUsers = true;
      users.users.root.initialPassword = "test";

      # SSH server for management access.
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "yes";
          PasswordAuthentication = true;
        };
      };

      # Open SSH port in the firewall.
      networking.firewall.allowedTCPPorts = [ 22 ];
    }
  ;
}
