# Shell / CLI config at the system level (no home-manager).
#
# We deliberately avoid home-manager so programs that rewrite their own
# dotfiles (many CLI tools do) stay writable. The user owns ~/.bashrc,
# ~/.gitconfig, etc. — these system-level settings only provide defaults
# via /etc and leave per-user overrides intact.
{ ... }:

{
  programs.bash = {
    enable = true;
    completion.enable = true;
    shellAliases = {
      ll = "ls -lAh";
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#Uwu";
      update = "cd /etc/nixos && nix flake update && sudo nixos-rebuild switch --flake .#Uwu";
      gc-old = "sudo nix-collect-garbage --delete-old";
    };
  };

  # System-wide git defaults. `~/.gitconfig` overrides these per-user.
  programs.git = {
    enable = true;
    config = {
      user = {
        name = "Jaide";
        email = "jaide@example.com"; # TODO: set your real email
      };
    };
  };

  # Starship prompt — installed system-wide; users opt in via their own
  # shell init (`eval "$(starship init bash)"`). We don't force it into
  # /etc/bashrc so users keep control of their prompt.
  programs.starship = {
    enable = true;
    settings = {
      add_new_line = false;
      line_break.disabled = true;
    };
  };
}