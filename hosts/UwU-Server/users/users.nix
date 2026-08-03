# UwU-Server host-specific user overrides.
_:
{
  nixos.hosts."UwU-Server" =
    _:

    {
      users.users."jaide" = {
        extraGroups = [ "networkmanager" "wheel" ];

        # TEMPORARY first-boot password — no password is set anywhere else in
        # the config, and without one the account is locked (no greeter login,
        # no sudo). CHANGE IMMEDIATELY after first login with `passwd`.
        initialPassword = "nixos";
      };
    }
  ;
}
