# Hermes Agent — Nous Research's terminal AI agent.
#
# Installs the CLI only (no NixOS service, no `hermes` system user, no
# secrets module). State stays in the user's own ~/.hermes/ and remains
# writable, matching the "no home-manager, user owns their dotfiles"
# convention used across this config.
#
# Flake input is declared in flake.nix; the overlay exposes the package
# as `pkgs.hermes-agent` so other modules can reference it too.
#
# The `mnemosyne-overlay` import (from ./mnemosyne.nix) is composed AFTER
# the upstream overlay so it can `.override { extraPythonPackages = ... }`
# on the upstream `pkgs.hermes-agent`. If mnemosyne.nix also added its own
# `nixpkgs.overlays` entry, the NixOS module-system merge order would put
# it BEFORE this upstream overlay (last-wins on `hermes-agent`), which
# would clobber the override. Composing here in a single list guarantees
# the order: upstream first, mnemosyne override second.
{ pkgs, inputs, ... }:

{
  nixpkgs.overlays = [
    inputs.hermes-agent.overlays.default
    (import ./mnemosyne-overlay.nix)
  ];

  environment.systemPackages = [ pkgs.hermes-agent ];
}