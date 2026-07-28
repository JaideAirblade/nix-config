# Users config for OwO-Family.
_:
{
  nixos.hosts."OwO-Family" =
    _:

    {
      users.users.jaide = {
        isNormalUser = true;
        extraGroups = [ "wheel" "networkmanager" "audio" "video" "input" ];
      };
    }
  ;
}
