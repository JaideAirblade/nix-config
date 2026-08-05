# Mnemosyne memory provider for Hermes Agent.
# https://github.com/mnemosyne-oss/mnemosyne
#
# This module wires the activation script that symlinks the installed
# `mnemosyne_hermes` package (a Nix store path that changes on every rebuild)
# into `~/.hermes/plugins/mnemosyne/` so Hermes' memory-provider discovery
# finds it. The actual packaging + `hermes-agent` override live in
# ./mnemosyne.overlay.nix, which is composed into `nixpkgs.overlays` by
# ./hermes-agent.nix AFTER the upstream overlay.
#
# User config (~/.hermes/config.yaml) is NOT touched — the user owns their
# dotfiles. Set `memory.provider: mnemosyne` once after the first rebuild.
_:
{
  nixos.modules.common =
    { pkgs, lib, ... }:

    let
      # The mnemosyne-hermes Python package, built by the overlay. We read it
      # from `pkgs.python312Packages.mnemosyne-hermes` (exposed by the overlay)
      # to resolve its site-packages path. This is the store path that changes
      # on every rebuild; the activation script re-points the symlink at it.
      mnemosyne-hermes = pkgs.python312Packages.mnemosyne-hermes;
      mnemosyne-hermes-dir = "${mnemosyne-hermes}/lib/python3.12/site-packages/mnemosyne_hermes";

      # Hermes plugin discovery paths for every Hermes user on this host.
      # On UwU the user is jaide; on UwU-Server the user is luna. We link
      # the plugin into every existing ~/.hermes/plugins/mnemosyne/ so
      # both single-user and server-side installs discover it.
      hermes-users = [ "jaide" "luna" ];
      hermes-plugins-for = user: "/home/${user}/.hermes/plugins/mnemosyne";
    in
    {
      # Symlink the installed mnemosyne_hermes package into Hermes' plugin
      # discovery directory on every rebuild. Idempotent — stale symlinks
      # pointing at old store paths are replaced. Runs after the system
      # profile is activated so the new store path exists. Skipped silently
      # if the user's ~/.hermes doesn't exist yet (first login creates it).
      system.activationScripts.mnemosyne-plugin = ''
        for user in ${lib.concatMapStringsSep " " (u: u) hermes-users}; do
          hermes_home="/home/$user/.hermes"
          if [ ! -d "$hermes_home" ]; then
            echo "mnemosyne-plugin: $hermes_home missing, skipping $user (will link on next rebuild)"
            continue
          fi
          plugins_dir="$hermes_home/plugins/mnemosyne"
          mkdir -p "$plugins_dir"
          find "$plugins_dir" -maxdepth 1 -type l -delete
          for f in ${mnemosyne-hermes-dir}/*; do
            ln -sfn "$f" "$plugins_dir/$(basename "$f")"
          done
          echo "mnemosyne-plugin: linked for $user"
        done
      '';
    }
  ;
}
