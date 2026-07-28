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
        rebuild = lib.mkForce "sudo nixos-rebuild switch --flake /etc/nixos#UwU";
        update = lib.mkForce "cd /etc/nixos && nix flake update && sudo nixos-rebuild switch --flake .#UwU";
      };

      programs.git.config.user = {
        name = lib.mkForce "JaideAirblade";
        email = lib.mkForce "mail@jaidechan.moe";
      };
    }
  ;
}
