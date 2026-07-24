# TSBW-W01800 host-specific shell overrides.
#
# Overrides the shared shell aliases to target this host's flake attr,
# and sets the git user.name/email for this machine (JaideAirblade +
# mail@jaidechan.moe, matching the original work home-manager config).
{ lib, ... }:

{
  programs.bash.shellAliases = lib.mkForce {
    ll = "ls -lAh";
    sf = "superfile";
    rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#TSBW-W01800";
    update = "cd /etc/nixos && nix flake update && sudo nixos-rebuild switch --flake .#TSBW-W01800";
    gc-old = "sudo nix-collect-garbage --delete-old";
  };

  # Git config — ported from the work host's home-manager/programs/git.nix.
  # The user.name/email match "JaideAirblade" / "mail@jaidechan.moe" from the
  # original work config.
  programs.git.config.user = {
    name = lib.mkForce "JaideAirblade";
    email = lib.mkForce "mail@jaidechan.moe";
  };
}