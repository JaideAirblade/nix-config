# Import-only entry for the theming module.
# Installs GTK/Qt theme packages and sets the env vars that make the
# compositors' toolkit theming pick them up. No home-manager — the user
# owns their dotfiles and selects the actual theme via their own settings.
{ ... }:

{
  imports = [
    ./theming.nix
    ./millennium-theme.nix
  ];
}