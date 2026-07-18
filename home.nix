# User-level configuration for `jaide`, applied by home-manager.
#
# This file is imported by flake.nix via
#   home-manager.users.jaide = import ./home.nix;
# and is applied automatically on every `sudo nixos-rebuild switch`.
#
# Per the guide: put anything that is per-user (packages only `jaide`
# needs, git/shell config, dotfiles) here rather than in
# configuration.nix, so it is isolated from the system config and more
# portable (home-manager also works on macOS / non-NixOS Linux).

{ config, pkgs, inputs, ... }:

{
  home.username = "jaide";
  home.homeDirectory = "/home/jaide";

  # Packages installed into jaide's user profile (not available to root
  # or other users — use `sudo <cmd>` if you need a tool as root, or add
  # it to environment.systemPackages in configuration.nix).
  home.packages = with pkgs; [
    # archives
    zip
    xz
    unzip
    p7zip

    # utils
    ripgrep # recursive content search (like the rg you're used to)
    jq      # JSON processor
    fzf     # fuzzy finder

    # misc
    file
    which
    tree

    # monitoring
    btop    # better htop

    # nix tooling
    nix-output-monitor # `nom` — richer `nix` output
  ];

  # Git — fill in your email when you have one.
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Jaide";
        email = "jaide@example.com"; # TODO: set your real email
      };
    };
  };

  # Bash with a couple of handy aliases.
  programs.bash = {
    enable = true;
    enableCompletion = true;
    bashrcExtra = ''
      export PATH="$PATH:$HOME/.local/bin:$HOME/bin"
    '';
    shellAliases = {
      ll = "ls -lAh";
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#Uwu";
      update = "cd /etc/nixos && nix flake update && sudo nixos-rebuild switch --flake .#Uwu";
      gc-old = "sudo nix-collect-garbage --delete-old";
    };
  };

  # A nicer prompt. Drop or replace if you prefer something else.
  programs.starship = {
    enable = true;
    settings = {
      add_new_line = false;
      line_break.disabled = true;
    };
  };

  # Keep this at the home-manager release your flake uses (release-26.05).
  home.stateVersion = "26.05";
}