# Network config for OwO-Family.
_:
{
  nixos.hosts."OwO-Family" =
    _:

    {
      networking = {
        hostName = "OwO-Family";
        networkmanager.enable = true;
      };
    }
  ;
}
