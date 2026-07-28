# Dendritic storage for merged lower-level NixOS modules.
#
# Automatically imported top-level feature modules contribute to a small set
# of reusable roles under `nixos.modules` or to one host under `nixos.hosts`.
# deferredModule is what makes contributions from independent files compose.
{ lib, ... }:
{
  options.nixos = {
    modules = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = { };
      description = "Composable NixOS role modules";
    };

    hosts = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = { };
      description = "Composable host-specific NixOS modules";
    };
  };
}
