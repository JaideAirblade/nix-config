# Users config for OwO-Family.
{ ... }:

{
  users.users.jaide = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" "input" ];
  };
}