# UwU-Server host-specific shell overrides.
_:
{
  nixos.hosts."UwU-Server" =
    { lib, ... }:

    {
      programs.bash.shellAliases = {
        rebuild = lib.mkForce "sudo nixos-rebuild switch --flake /etc/nixos#UwU-Server";
        update = lib.mkForce "cd /etc/nixos && nix flake update && sudo nixos-rebuild switch --flake .#UwU-Server";
      };

      programs.git.config.user = {
        name = lib.mkForce "JaideAirblade";
        email = lib.mkForce "mail@jaidechan.moe";
      };
    }
  ;
}
