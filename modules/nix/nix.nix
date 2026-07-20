# Nix / nixpkgs settings: flakes, unfree, editor.
{ ... }:

{
  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # We're fully on Flakes — no nix-channel. Disabling removes the channel
  # tools/config so nothing accidentally drifts the system off the flake.lock.
  nix.channel.enable = false;

  environment.variables.EDITOR = "vim";
}