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

  # NOTE: Previously used `gh auth git-credential` as a git credential helper
  # for HTTPS GitHub access. Now switched to SSH — the SSH key is deployed
  # via sops-nix (modules/secrets/secrets.nix) and git is configured to use
  # git@github.com: instead of https://github.com/.
}