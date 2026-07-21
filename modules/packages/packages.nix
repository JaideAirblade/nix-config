# System-wide base packages shared across all hosts.
#
# Only the truly universal CLI tools and terminals live here — anything
# host-specific (Discord, seanime, Geary, Betterbird, disk-recovery,
# network analysis tools, ...) lives in hosts/<name>/packages/ so each
# host pulls only what it actually wants.
#
# Per-user tools are intentionally NOT managed here — the user owns their
# dotfiles and per-user installs (no home-manager).
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    vim   # editor of last resort
    wget
    git   # flakes pulls deps via git; also useful as a user tool
    gh    # GitHub CLI — `gh auth login`, `gh pr create`, etc.
    just  # command runner for the Justfile (see ~/nixos/Justfile)
    ripgrep
    jq
    fzf
    file
    which
    tree
    btop     # better htop
    nix-output-monitor # `nom` — richer `nix` output

    # Terminals — every host wants a terminal installed system-wide.
    ghostty
  ];

  programs.firefox.enable = true;

  # Wire gh as the git credential helper for github.com.
  # We can't use `gh auth setup-git` because programs.git.config symlinks
  # ~/.config/git/config into the read-only nix store, so the credential
  # helper goes here in the NixOS-managed git config instead.
  # The `!` prefix is required — without it git tries to run
  # `git credential-gh` (a non-existent binary) instead of treating
  # the value as a shell command.
  programs.git.config.credential."https://github.com" = {
    helper = "!gh auth git-credential";
  };
}