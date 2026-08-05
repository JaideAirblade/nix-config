# Persistent authorization support for the USB4-connected Beelink Mate SE.
_:
{
  nixos.hosts."UwU-Server" =
    _:
    {
      # boltd stores explicitly enrolled Thunderbolt/USB4 identities and
      # automatically re-authorizes trusted devices according to their policy.
      # The Mate SE itself is enrolled once after deployment with policy=auto;
      # no broad or wildcard device authorization is configured here.
      services.hardware.bolt.enable = true;
    };
}
