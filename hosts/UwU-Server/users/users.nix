# UwU-Server host-specific user overrides.
_:
{
  nixos.hosts."UwU-Server" =
    _:

    {
      users.users."jaide" = {
        extraGroups = [ "networkmanager" "wheel" ];
        # The authorized SSH key is the only bootstrap credential. Set a login
        # password with `passwd` over that authenticated session if remote sudo is
        # needed; never put a plaintext bootstrap password in the Nix store.
      };
    }
  ;
}
