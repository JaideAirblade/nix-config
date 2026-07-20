# User accounts. Per-user dotfiles are NOT managed here (we dropped
# home-manager on purpose — programs that write their own config stay
# writable). This only declares the account itself and its groups.
#
# Defaults are written with lib.mkDefault so a host can override the
# description or add host-specific groups (e.g. UwU adds input/uinput
# via the macrotool/devices modules). Both hosts add `wireshark` for
# packet capture without sudo. Hosts set extraGroups via lib.mkForce
# or append via the module-system merge.
{ lib, ... }:

{
  users.users."jaide" = {
    isNormalUser = true;
    description = lib.mkDefault "Jaide";
    extraGroups = lib.mkDefault [ "networkmanager" "wheel" ];
  };
}