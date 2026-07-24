# UwU host-specific shell overrides.
#
# Overrides the shared shell aliases to target this host's flake attr,
# and sets the git user.name/email for this machine.
{ lib, ... }:

{
  programs.bash.shellAliases = lib.mkForce {
    ll = "ls -lAh";
    sf = "superfile";
    rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#UwU";
    update = "cd /etc/nixos && nix flake update && sudo nixos-rebuild switch --flake .#UwU";
    gc-old = "sudo nix-collect-garbage --delete-old";
  };

  programs.git.config.user = {
    name = lib.mkForce "JaideAirblade";
    email = lib.mkForce "mail@jaidechan.moe";
  };
}