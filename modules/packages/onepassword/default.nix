# Import-only entry for the 1Password module.
# Enables the 1Password GUI + CLI and wires up browser-extension unlocking
# and polkit-based system authentication. No home-manager — user-owned
# dotfiles (SSH agent socket, git signing) stay writable.
{ ... }:

{
  imports = [ ./onepassword.nix ];
}