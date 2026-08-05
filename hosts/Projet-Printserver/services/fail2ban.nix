# Fail2ban for the print server VM.
#
# This host is the most critical fail2ban target because it allows SSH
# password authentication (for AD users via SSSD/PAM). Fail2ban protects
# against brute-force password attacks on both SSH and the print services.
#
# The NixOS module auto-creates the sshd jail. We whitelist the lab subnet
# so AD workstations and the domain controller are never accidentally banned.
_:
{
  nixos.hosts."Projet-Printserver" =
    _:
    {
      services.fail2ban = {
        enable = true;

        # Lab subnet — DC, AD clients, and admin workstations.
        # Merged with the shared VPN mesh whitelist (10.100.0.0/24).
        ignoreIP = [ "192.168.100.0/24" ];
      };
    }
  ;
}
