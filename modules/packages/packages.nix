# System-wide packages. Only things every user (and root) should have.
# Per-user tools are intentionally NOT managed here — the user owns their
# dotfiles and per-user installs (no home-manager).
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    vim   # editor of last resort
    wget
    git   # flakes pulls deps via git; also useful as a user tool
    # handy CLI tools available to everyone
    ripgrep
    jq
    fzf
    file
    which
    tree
    btop     # better htop
    nix-output-monitor # `nom` — richer `nix` output
    # desktop apps
    ghostty  # GPU-accelerated terminal (config lives in ~/.config/ghostty)
    kitty    # fallback terminal, also GPU-accelerated
    nautilus # GNOME Files — graphical file manager
  ];

  programs.firefox.enable = true;
}