# UwU host-specific shell overrides.
#
# Overrides the shared shell aliases to target this host's flake attr,
# and sets the git user.name/email for this machine.
_:
{
  nixos.hosts."UwU" =
    { lib, ... }:

    {
      programs.bash.shellAliases = {
        # Point at the actual flake checkout on this host. The legacy
        # /etc/nixos#UwU path is a NixOS default that no longer matches
        # this host's working tree (which lives at /home/jaide/nixos).
        # Use `rebuild` from any jaide bash shell after the next switch
        # to deploy from this clone.
        rebuild = lib.mkForce "sudo nixos-rebuild switch --flake /home/jaide/nixos#UwU";
        update = lib.mkForce "cd /home/jaide/nixos && nix flake update && sudo nixos-rebuild switch --flake .#UwU";
      };

      programs.git.config.user = {
        name = lib.mkForce "JaideAirblade";
        email = lib.mkForce "mail@jaidechan.moe";
      };
    }
  ;
}
