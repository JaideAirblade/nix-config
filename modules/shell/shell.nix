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

      # ─────────────────────────────────────────────────────────────────
      # zoxide — smarter `cd` that learns your habits.
      # ─────────────────────────────────────────────────────────────────
      # Replaces the host's `cd` with one that tracks directories you've
      # visited and lets you jump to them with partial names:
      #   z foo         # cd to the highest-ranked dir matching "foo"
      #   zi foo        # interactive picker (fzf if installed)
      # The bash integration auto-initialises on every interactive shell,
      # so `cd` is transparently upgraded. Defaults to true for enableBash
      # / enableZsh / enableFish in the upstream module.
      #
      # Note: we deliberately do NOT also enable `programs.comma`. Comma
      # is a Rust reimplementation of the same idea; enabling both would
      # make them fight each other on the `cd` hook. Zoxide is the more
      # mature option and is what the user picked.
      programs.zoxide.enable = true;

      # ─────────────────────────────────────────────────────────────────
      # nh — alternative Nix CLI for switch/build/update.
      # ─────────────────────────────────────────────────────────────────
      # nh is a faster, more ergonomic front-end for nix operations that
      # replaces the usual `nixos-rebuild` / `nix build` invocations. It
      # uses flake-native state tracking so you can do `nh os switch`
      # instead of `sudo nixos-rebuild switch --flake /etc/nixos#UwU`.
      # `flake` is left null by default — users set `NH_FLAKE` in their
      # shell init or pass --flake explicitly per invocation.
      programs.nh.enable = true;
    }
  ;
}
