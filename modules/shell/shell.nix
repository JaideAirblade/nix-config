# Shell / CLI config at the system level (no home-manager).
#
# We deliberately avoid home-manager so programs that rewrite their own
# dotfiles (many CLI tools do) stay writable. The user owns ~/.bashrc,
# ~/.gitconfig, etc. — these system-level settings only provide defaults
# via /etc and leave per-user overrides intact.
# Note: the inner function takes `pkgs` so we can pull in
# CLI tools (ripgrep-all, ocrmypdf, ...) that don't have a
# `programs.X.enable` option in upstream nixpkgs. The shell-level
# tools (zoxide, nh, starship, ...) are still wired via their
# programs.X.enable options, which compose neatly with the
# NixOS module system.
_:
{
  nixos.modules.common =
    { lib, pkgs, ... }:

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
      # zoxide's `~/.bashrc` integration is sensitive to ordering: the
      # upstream doctor message fires when the hook runs but the
      # database init (the `_ZO_DATA` / `_ZO_RESOLVE_SYMLINKS` / preexec
      # registration) is later in the file than something that uses
      # `cd`. The user ran `z` and got:
      #   zoxide: detected a possible configuration issue.
      #   Please ensure that zoxide is initialized right at the end
      #   of your shell configuration file (usually ~/.bashrc).
      # The upstream module's enableBashIntegration places the
      # `eval $(zoxide init bash)` line in interactiveShellInit; we
      # ALSO pin it with mkAfter so our copy is appended last (and
      # therefore runs after every other module's bashrc additions
      # like ours and the user's iNiR launcher). Net effect: zoxide
      # is the last thing to run, so its doctor warning stays quiet.
      # zoxide's doctor message fires when `cd` (or anything that
      # triggers prompter/preexec) runs BEFORE zoxide's init bash
      # has had a chance to register its preexec hook. The upstream
      # programs.zoxide module writes the init to
      # programs.bash.interactiveShellInit with default ordering;
      # when bash-completion / starship / etc. add their own
      # interactiveShellInit lines, the relative order is module-
      # system-defined and zoxide can land BEFORE bash-completion's
      # `set +h`, which is allowed. The user actually got the
      # doctor warning on UwU, though, so something in their flow
      # is triggering it. We pin zoxide init at the END with
      # mkAfter so it's the last line, and we use --cmd cd so
      # zoxide wraps the `cd` builtin directly (avoids the hint
      # that the upstream init does NOT do by default).
      programs.bash.interactiveShellInit = lib.mkAfter
        ''
        eval "$(${pkgs.zoxide}/bin/zoxide init bash --cmd cd)"
        '';

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

      # ─────────────────────────────────────────────────────────────────
      # ripgrep-all — rg with PDF / Office / e-book / archive support
      # ─────────────────────────────────────────────────────────────────
      # Ripgrep-all (rga) extends ripgrep with adapters that pre-extract
      # text from PDFs, .docx, .epub, .zip, .tar.gz, etc. so you can grep
      # the contents of binary archive files as if they were plain text:
      #   rga foo notes.pdf
      #   rga --type pdf "needle"
      # rga respects the same flags as rg (recursive, hidden, glob), so
      # its alias is a drop-in. The system already has `rg` from
      # packages.nix; this is the augmented binary that knows about
      # archive formats.
      #
      # ─────────────────────────────────────────────────────────────────
      # ripgrep-all + ocrmypdf — pull-in CLI tools without NixOS modules
      # ─────────────────────────────────────────────────────────────────
      # These are not `programs.X.enable` options in upstream nixpkgs —
      # they are pure Python/Cargo packages with no module wrapping. We
      # add them directly to environment.systemPackages. The list is
      # defined once at the end of the module so the module system's
      # automatic merging doesn't double-define the key.
      #
      # ripgrep-all (rga) — augments rg with PDF, Office, e-book, and
      # archive adapters so you can grep into binary file contents:
      #   rga foo notes.pdf
      # rga respects the same flags as rg, so it is a drop-in replacement.
      # Closure is small (~5MB).
      #
      # ocrmypdf — adds a searchable OCR text layer to scanned PDFs.
      #   ocrmypdf input.pdf output.pdf          # lossless, ~2x size
      #   ocrmypdf --optimize 1 input.pdf out.pdf # smaller, recompresses
      #   ocrmypdf -l deu+eng input.pdf out.pdf    # multi-language
      # Closure is heavy (~200MB compressed) because it pulls in
      # tesseract 5 + pikepdf + pypdfium2 + pillow + ghostscript, but
      # the binary is small and there is no daemon.
      environment.systemPackages = [ pkgs.ripgrep-all pkgs.ocrmypdf ];
    }
  ;
}
