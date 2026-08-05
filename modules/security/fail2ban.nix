# Fail2ban — shared defaults for intrusion prevention.
#
# Sets defaults that apply when a host enables services.fail2ban.enable.
# Does NOT enable fail2ban globally — only hosts with exposed services
# should opt in.
#
# The NixOS fail2ban module auto-creates an sshd jail when openssh.enable
# is true, auto-sets LogLevel=VERBOSE for sshd logging, and uses
# nftables-multiport as the ban action (nftables is enabled in the shared
# firewall module).
#
# To enable on a host:
#   services.fail2ban.enable = true;
#   # Optionally add host-specific whitelists (merged with VPN subnet below):
#   services.fail2ban.ignoreIP = [ "192.168.100.0/24" ];
_:
{
  nixos.modules.common =
    { lib, ... }:
    {
      services.fail2ban = {
        # Progressive banning — repeat offenders get exponentially longer bans
        # (bantime * 1, 2, 4, 8, 16, 32 ... up to maxtime).
        bantime = lib.mkDefault "1h";
        bantime-increment.enable = lib.mkDefault true;
        bantime-increment.maxtime = lib.mkDefault "1w";

        # Whitelist the AmneziaWG VPN mesh — trusted internal traffic.
        # Per-host entries (lab subnets, etc.) are merged by concatenation.
        ignoreIP = [ "10.100.0.0/24" ];
      };
    }
  ;
}
