# Shell / CLI config at the system level (no home-manager).
#
# We deliberately avoid home-manager so programs that rewrite their own
# dotfiles (many CLI tools do) stay writable. The user owns ~/.bashrc,
# ~/.gitconfig, etc. — these system-level settings only provide defaults
# via /etc and leave per-user overrides intact.
{ lib, ... }:

{
  programs.bash = {
    enable = true;
    completion.enable = true;
    shellAliases = {
      ll = "ls -lAh";
      sf = "superfile";
      # Each host overrides the `rebuild`/`update` aliases with its own
      # flake target via lib.mkForce in hosts/<name>/shell.nix.
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos";
      update = "cd /etc/nixos && nix flake update && sudo nixos-rebuild switch --flake .";
      gc-old = "sudo nix-collect-garbage --delete-old";
    };
  };

  # System-wide git defaults. `~/.gitconfig` overrides these per-user.
  # Hosts can override the user.name/user.email via lib.mkForce.
  programs.git = {
    enable = true;
    config = {
      user = {
        name = lib.mkDefault "JaideAirblade";
        email = lib.mkDefault "mail@jaidechan.moe";
      };
    };
  };

  # Starship prompt — installed system-wide; users opt in via their own
  # shell init (`eval "$(starship init bash)"`). We don't force it into
  # /etc/bashrc so users keep control of their prompt.
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      line_break.disabled = true;
    };
  };
}