# Shell / CLI config at the system level (no home-manager).
#
# We deliberately avoid home-manager so programs that rewrite their own
# dotfiles (many CLI tools do) stay writable. The user owns ~/.bashrc,
# ~/.gitconfig, etc. — these system-level settings only provide defaults
# via /etc and leave per-user overrides intact.
_:
{
  nixos.modules.common =
    { lib, ... }:

    {
      programs.bash = {
        enable = true;
        completion.enable = true;
        shellAliases = {
          ls = "eza";
          ll = "eza -lAhno";
          la = "eza -a";
          lt = "eza --tree --level=2";
          sf = "superfile";
          # Hosts may override only these values with lib.mkForce.
          rebuild = "sudo nixos-rebuild switch --flake /etc/nixos";
          update = "cd /etc/nixos && nix flake update && sudo nixos-rebuild switch --flake .";
          gc = "sudo nix-collect-garbage";
        };
      };

      # System-wide git defaults. `~/.gitconfig` overrides these per-user.
      # Hosts can override the user.name/user.email via lib.mkForce.
      programs.git = {
        enable = true;
        config = {
          core.pager = "delta";
          interactive.diffFilter = "delta --color-only";
          delta = {
            navigate = true;
            side-by-side = true;
            line-numbers = true;
          };
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
  ;
}
