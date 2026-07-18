# User accounts. Per-user dotfiles are NOT managed here (we dropped
# home-manager on purpose — programs that write their own config stay
# writable). This only declares the account itself and its groups.
{ ... }:

{
  users.users."jaide" = {
    isNormalUser = true;
    description = "Jaide";
    extraGroups = [ "networkmanager" "wheel" ];
  };
}